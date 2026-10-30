local Model=require("../Games/Last Stand")
local passed=0
local function check(ok) assert(ok);passed+=1 end
local city={W=1000,H=1000,evacSites={{x=100,y=100},{x=700,y=700}}}
local sim={city=city,agents={},evacs={},time=10}
local function human(x,y) return {x=x,y=y,kind="Human"} end
check(Model.point(0,0,city))
check(not Model.point(0/0,10,city))
check(not Model.point(math.huge,0,city))
check(not Model.point(-1,0,city))
check(not Model.point(1001,0,city))
check(Model.evac(sim,1,90)==nil)
sim.agents={human(110,110),human(120,120),human(705,705)}
check(Model.evac(sim,2,90)==city.evacSites[1])
sim.evacs={{site=city.evacSites[1],x=100,y=100}}
check(Model.evac(sim,1,90)==city.evacSites[2])
sim.evacs={};table.insert(sim.agents,{kind="Zombie",x=100,y=100})
check(Model.evac(sim,1,90)==city.evacSites[2])
sim.agents[4].hidden=true
check(Model.evac(sim,2,90)==city.evacSites[1])
sim.agents[1].infected=true
check(Model.evac(sim,2,90)==nil)
sim.agents={human(100,100),human(101,102),human(105,106)}
for _,a in ipairs(sim.agents) do a.infected=true;a.revealUntil=20 end
local target=Model.target(sim,"Infected",3,65)
check(target and target.count==3)
sim.agents[1].revealUntil=5
check(Model.target(sim,"Infected",3,65)==nil)
sim.agents={{kind="Zombie",hidden=true,x=100,y=100}}
check(Model.target(sim,"Zombie",1,85)==nil)
sim.agents[1].hidden=false
check(Model.target(sim,"Zombie",1,85).count==1)
local raw={tool="Evac",x=100,y=100}
local step=Model.step(raw,city);raw.x=999
check(step.x==100)
check(Model.step({tool="Evac",x=-2,y=10},city)==nil)
sim.sites={{reported=false,x=100,y=100},{reported=true,x=500,y=500}};sim.recons={}
check(Model.report(sim)==sim.sites[2])
sim.recons={{x=500,y=500}}
check(Model.report(sim)==nil)
check(Model.roundKey({level={name="Easy"}})==Model.roundKey({level={map="manhattan",name="Easy"}}))
check(Model.roundKey({level={map="manhattan",name="Easy"}})~=Model.roundKey({level={map="manhattan",name="Hard"}}))
check(Model.roundKey({level={map="manhattan",id="tutorial"}})~=Model.roundKey({level={map="brooklyn",id="tutorial"}}))
print("Last Stand planning checks passed:",passed)
