"""Exercise the real custom-script scanner with executor filesystem fixtures.
Run: python Tests/test_custom_scripts.py path/to/luau.exe
"""
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
source = (repo / 'Altair.lua').read_text(encoding='utf-8')
start = source.index('altairValues.customScriptFileStem = function(')
end = source.index('altairValues.closeGameDetection = function(', start)
setup = r'''
local folder = "Altair/Custom Scripts"
local altairValues = {altairFolder="Altair",customScriptsFolder="Custom Scripts"}
local placeId = 286090429
local files, decoded, writes, notifications = {}, {}, {}, {}
local enumerationError
local function isfolder() return true end
local function makefolder() end
local function isfile(path) return files[path] ~= nil or writes[path] ~= nil end
local function listfiles()
 if enumerationError then error(enumerationError) end
 local result = {} for path in pairs(files) do table.insert(result,path) end return result
end
local function readfile(path) return assert(files[path], "missing file") end
local function writefile(path,raw) writes[path] = raw end
local function delfile(path) files[path] = nil end
local function warn() end
local function queueNotification(title, body) table.insert(notifications,{title,body}) end
local httpService = {JSONDecode=function(_,raw) return assert(decoded[raw],"invalid JSON") end}
local marketplaceService = {GetProductInfo=function() return {Name="☢️ QS Energy Research Facility"} end}
'''
cases = r'''
local stem=altairValues.customScriptFileStem
assert(stem("☢️ QS Energy Research Facility") == "QS Energy Research Facility")
assert(stem("日本語") == "Custom Script")
assert(stem("CON") == "Custom CON")
assert(stem("A/B\\C:\n") == "ABC")
assert(stem("...") == "Custom Script")
assert(stem(".Example") == ".Example")
print("PASS portable filenames")
local arsenal={ScriptTitle="Arsenal",ScriptSubtitle="Arsenal script",PlaceIds={286090429},Source="return true"}
decoded.valid=arsenal
files[folder.."/Arsenal.altair"]="valid"
files[folder.."/Broken.json"]="broken"
local detected=altairValues.scanCustomScripts()
assert(detected.ScriptTitle=="Arsenal" and #altairValues.customScripts==1)
print("PASS current PlaceId and corrupt sibling")
arsenal.PlaceIds={"286090429"}
assert(altairValues.scanCustomScripts().ScriptTitle=="Arsenal")
arsenal.PlaceIds=nil;arsenal.PlaceId=286090429
assert(altairValues.scanCustomScripts().ScriptTitle=="Arsenal")
arsenal.PlaceId=nil;arsenal.Games={286090429}
assert(altairValues.scanCustomScripts().ScriptTitle=="Arsenal")
arsenal.Games={123}
assert(altairValues.scanCustomScripts()==nil)
print("PASS ID aliases, string IDs, and unrelated places")
files={};writes={}
decoded.numeric={ScriptTitle="3039795291",ScriptSubtitle="Energy script",PlaceIds={placeId},LuaFile="Energy.lua"}
files[folder.."/3039795291.altair"]="numeric"
files[folder.."/QS Energy Research Facility.altair"]="broken"
detected=altairValues.scanCustomScripts()
assert(detected and detected.DefinitionFile==folder.."/QS Energy Research Facility (2).altair")
assert(writes[detected.DefinitionFile]=="numeric")
assert(files[folder.."/3039795291.altair"]==nil)
assert(detected.ScriptTitle=="3039795291")
print("PASS automatic naming preserves content and avoids collisions")
enumerationError="No mapping for the Unicode character exists"
local result,err=altairValues.scanCustomScripts()
assert(result==nil and string.find(err,enumerationError,1,true))
assert(#notifications==1 and string.find(notifications[1][2],"Rename",1,true))
print("PASS actionable enumeration failure")
'''
with tempfile.TemporaryDirectory() as directory:
    test = Path(directory) / 'custom_scripts.luau'
    test.write_text(setup + source[start:end] + cases, encoding='utf-8')
    subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'luau', str(test)], check=True)
