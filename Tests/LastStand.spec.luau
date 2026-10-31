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
-- Rescue ownership and lifecycle: no unsolicited placement in assist mode.
local book=Model.newRescues()
sim.evacs={};sim.fires={};sim.charred={}
check(Model.repeatRescue(book,sim,"Evac")==nil)
sim.evacs={{x=100,y=100,expire=50}}
Model.observeRescues(book,sim,{Evac=false},false,0)
check(#book.order==0)
book.seen={};Model.observeRescues(book,sim,{Evac=true},false,1)
check(#book.order==1 and book.points[book.order[1]].x==100)
check(Model.repeatRescue(book,sim,"Evac")==nil)
sim.evacs={};Model.observeRescues(book,sim,{Evac=true},false,51)
local repeatPoint,index=Model.repeatRescue(book,sim,"Evac")
check(repeatPoint.x==100 and repeatPoint.y==100 and index==1)
Model.issuedRescue(book,city,"Evac",100,100,52)
sim.evacs={{x=100,y=100,expire=100}}
Model.observeRescues(book,sim,{Evac=true},false,53)
check(#book.order==1)
-- The engine / multiplayer mirror can replace active table objects every tick.
sim.evacs={{x=100,y=100,expire=100}}
Model.observeRescues(book,sim,{Evac=true},false,54)
check(#book.order==1)
sim.evacs[2]={x=700,y=700,expire=101}
Model.observeRescues(book,sim,{Evac=true},false,55)
check(#book.order==2)
sim.evacs={};book.cursor.Evac=1
local second=Model.repeatRescue(book,sim,"Evac")
check(second.x==700)
book.cursor.Evac=2;check(Model.repeatRescue(book,sim,"Evac").x==100)
-- Autonomous extracts must not seed manual-repeat mode, even after ten seconds,
-- clearing observed snapshots, or switching out of full autofarm.
book=Model.newRescues();Model.issuedRescue(book,city,"Evac",100,100,0)
sim.evacs={{x=100,y=100,expire=100}}
Model.observeRescues(book,sim,{Evac=true},true,20)
book.seen={};Model.observeRescues(book,sim,{Evac=true},false,21)
check(#book.order==0)
sim.evacs={};Model.observeRescues(book,sim,{Evac=true},false,101)
sim.evacs={{x=100,y=100,expire=150}}
Model.observeRescues(book,sim,{Evac=true},false,102)
check(#book.order==1) -- a genuinely new player-started extract is accepted
-- Rooftops repeat on the clicked building, not the different boarding entrance.
city.roofs={{200,200,20,20},{800,800,20,20}}
function city:roofAt(x,y) if x==200 and y==200 then return 1 elseif x==800 and y==800 then return 2 end end
function city:nearestWalkable(x,y) return x+20,y end
local roofRecord={rooftop=true,roof=1,x=220,y=200,expire=200}
local roofPoint=Model.rescue(city,roofRecord)
check(roofPoint.x==200 and roofPoint.y==200 and roofPoint.key=="roof:1")
check(Model.rescue(city,{rooftop=true,roof=999})==nil)
check(Model.rescue(city,{dead=true,rooftop=true,roof=1})==nil)
book=Model.newRescues();sim.evacs={roofRecord}
Model.observeRescues(book,sim,{Rooftop=true},false,1)
check(#book.order==1 and Model.repeatRescue(book,sim,"Rooftop")==nil)
sim.evacs={};check(Model.repeatRescue(book,sim,"Rooftop").x==200)
sim.fires[1]=true;check(Model.repeatRescue(book,sim,"Rooftop")==nil)
sim.fires={};sim.charred[1]=true;check(Model.repeatRescue(book,sim,"Rooftop")==nil)
sim.charred={};sim.agents={human(225,200),human(230,201),human(800,800)}
check(Model.rooftop(sim,2,100).roof==1)
sim.evacs={roofRecord};check(Model.rooftop(sim,1,100).roof==2)
sim.evacs={};sim.fires[1]=true;check(Model.rooftop(sim,2,100)==nil)
sim.fires={};sim.agents={human(319,299)}
check(Model.rooftop(sim,1,100)==nil) -- neighboring spatial bins are not enough
sim.agents={};check(Model.rooftop(sim,1,100)==nil)
-- HQ selection protects people, ignores concealed / dead entities, and retargets.
sim.agents={{id=1,kind="Zombie",x=100,y=100},{id=2,kind="Zombie",x=700,y=700},human(700,700),human(710,710)}
check(Model.hqTarget(sim,{x=100,y=100},{}).id==2)
check(Model.hqTarget(sim,{x=100,y=100},{[2]=true}).id==1)
sim.agents[2].dead=true;check(Model.hqTarget(sim,{x=100,y=100},{}).id==1)
sim.agents[1].hidden=true;check(Model.hqTarget(sim,{x=100,y=100},{})==nil)
sim.agents[1].hidden=false
local clustered=Model.clusters(sim,"Zombie",100)
check(#clustered==1 and clustered[1].count==1)
check(Model.clusters(sim,"Healthy",100)[1].count==2)
local square=Model.square(city,{x=0,y=1000},70)
check(square[1][1]==0 and square[3][2]==1000)
check(Model.square({W=50,H=50},{x=10,y=10},70)==nil)
-- Never declare a perimeter complete because of a short / dead / unrelated wall.
local segment={x=0,y=0,x2=70,y2=0}
local function wall(x1,x2) return {x1=x1,y1=0,x2=x2,y2=0,gate=true,hp=100} end
check(Model.gateCovered(segment,{wall(0,70)}))
check(not Model.gateCovered(segment,{wall(20,40)}))
check(Model.gateCovered(segment,{wall(-10,35),wall(35,80)}))
check(not Model.gateCovered(segment,{wall(0,25),wall(35,70)}))
local destroyed=wall(0,70);destroyed.hp=0;check(not Model.gateCovered(segment,{destroyed}))
local ordinary=wall(0,70);ordinary.gate=false;check(not Model.gateCovered(segment,{ordinary}))
local offset=wall(0,70);offset.y1=10;offset.y2=10;check(not Model.gateCovered(segment,{offset}))
check(not Model.gateCovered({x=0,y=0,x2=0,y2=0},{wall(0,70)}))
local ratio,margin=Model.preservation({startPop=1000,pop={citizens=850}})
check(ratio==.85 and margin==0)
check(Model.preservation({startPop=1000,pop={citizens=849}})<.85)
check(Model.preservation({startPop=0,pop={citizens=1}})==nil)
check(Model.preservation({startPop=1000})==nil)
check(Model.roundKey({level={name="Nightmare",kitMap="base"}})~=Model.roundKey({level={name="Nightmare",kitMap="city"}}))
sim.agents={};sim.forts={};sim.builds={};sim.fires={};sim.charred={}
check(Model.sentry(sim,{x=200,y=200},40).x==200)
sim.builds={{kind="fort",x=200,y=200}}
check(Model.sentry(sim,{x=200,y=200},40)==nil) -- do not buy another while one builds
sim.builds={};sim.forts={{x=200,y=200}}
check(Model.sentry(sim,{x=200,y=200},40)==nil)
sim.forts={};sim.charred[1]=true
check(Model.sentry(sim,{x=200,y=200},40)==nil)
sim.charred={};check(Model.sentry(sim,{x=500,y=500},40)==nil)
-- Nightmare decisions use real pressure and preserve treatment funds.
local severe={level={name="Nightmare",stars=5,surviveDays=3},time=50,day=1,budget=400,startPop=4000,pop={citizens=4000,infected=50,visibleZombies=30}}
local policy=Model.policy(severe,250)
check(policy.reserve==0 and not policy.build and policy.minCures==4)
severe.pop.infected=0;severe.pop.visibleZombies=0
check(Model.policy(severe,250).reserve==40)
check(not Model.policy(severe,250).build)
severe.budget=1100;check(Model.policy(severe,250).build)
severe.day=4;check(Model.policy(severe,250).minCures==1)
-- Fresh public tracking reports outrank stale outbreak guesses, with coverage
-- and expiration preventing repeated purchases at the same clue.
local clues={city=city,time=20,suspects={{x=300,y=300,n=8,born=19,expire=30},{x=800,y=800,n=2,born=19,expire=30}},recons={}}
local intel=Model.intel(clues,{},175)
check(intel.x==300)
clues.recons={{x=300,y=300,r=175}}
check(Model.intel(clues,{},175).x==800)
clues.recons={};check(Model.intel(clues,{[intel.intelKey]=19},175).x==800)
clues.time=31;check(Model.intel(clues,{},175)==nil)
-- Native vaccine shells cannot cure patient zero / boss seeds. Do not spend
-- on those. Assists use revealed cases; solo full mode can aim native area
-- treatment using locally available NPC state, including unrevealed carriers.
local medical={time=10,agents={{x=100,y=100,kind="Human",infected=true,revealUntil=20,patientZero=true}}}
check(Model.treatment(medical,70,30)==nil)
medical.agents[1].patientZero=nil;medical.agents[1].bossSeed=true
check(Model.treatment(medical,70,30)==nil)
medical.agents[1].bossSeed=nil;medical.agents[1].revealUntil=0
check(Model.treatment(medical,70,30)==nil)
medical.agents[1].revealUntil=20
check(Model.treatment(medical,70,30).count==1)
medical.agents={{x=68,y=100,kind="Human",infected=true,revealUntil=20},{x=72,y=100,kind="Human",infected=true,revealUntil=20}}
check(Model.treatment(medical,70,30).count==2) -- across an old grid boundary
-- Special enemies have different urgency and undisturbed Weepers stay alone.
check(Model.specialWeight({special="runner"})>Model.specialWeight({}))
check(Model.specialWeight({special="wrecker"})>Model.specialWeight({special="brute"}))
check(Model.specialWeight({special="weeper",weeperMood="crying"})==0)
check(Model.specialWeight({special="weeper",weeperMood="angry"})>0)
local specials={time=10,agents={{id=1,x=100,y=100,kind="Zombie",special="weeper",weeperMood="crying"}},evacs={},walls={}}
check(Model.hqTarget(specials,{x=0,y=0},{})==nil)
check(Model.support(specials,1)==nil)
specials.agents={{id=1,x=100,y=100,kind="Zombie"},{id=2,x=110,y=100,kind="Zombie",special="bloater"}}
check(Model.hqTarget(specials,{x=0,y=0},{}).id==2)
check(Model.support(specials,2).special=="bloater")
local source={id=3,x=400,y=400,kind="Zombie",hiddenUntil=40}
specials.agents={source}
check(Model.support(specials,2).seed==true) -- do not wait for a source to create a group
check(Model.support(specials,2,{{x=400,y=400,untilTime=20}})==nil)
for i=1,4 do table.insert(specials.agents,{kind="Soldier",medicTeam=true,x=400,y=400})end
check(Model.support(specials,2)~=nil) -- medics provide healing, not firepower
for i=2,5 do specials.agents[i].medicTeam=nil end
check(Model.support(specials,2)==nil)
check(Model.responseTool({seed=true},{Ghosts=true,Hunters=true})=="Ghosts")
check(Model.responseTool({special="brute"},{Ghosts=true,Hunters=true})=="Hunters")
check(Model.responseTool({special="brute"},{Strike=true})=="Strike")
local reports={city=city,time=20,pop={hiddenZombies=0},suspects={{x=300,y=300,n=6,r=45,born=19,expire=35}}}
local treatment=Model.reportTreatment(reports,94,{})
check(treatment and treatment.count==6)
check(Model.reportTreatment(reports,94,{[treatment.reportKey]=true})==nil)
reports.time=24;check(Model.reportTreatment(reports,94,{})==nil) -- stale position cannot guide a shell
reports.time=20;reports.suspects[1].r=200;check(Model.reportTreatment(reports,94,{})==nil)
reports.suspects[1].r=40;reports.suspects[1].n=1
check(Model.reportTreatment(reports,94,{})~=nil)
reports.pop.hiddenZombies=1;check(Model.reportTreatment(reports,94,{})==nil) -- investigate an unknown lone source
local pickups={time=10,isNight=true,candyCollected=0,crates={{x=1,y=1,candy=true,expire=12},{x=2,y=2,expire=11},{x=3,y=3,candy=true,expire=9},{x=4,y=4,candy=true,expire=15,dead=true}}}
check(#Model.pickups(pickups,true,true,10)==2)
check(Model.pickups(pickups,true,true,10)[1].candy==true)
check(#Model.pickups(pickups,false,true,10)==1)
check(#Model.pickups(pickups,true,false,10)==1)
pickups.isNight=false;check(#Model.pickups(pickups,false,true,10)==0)
pickups.isNight=true;pickups.candyCollected=10;check(#Model.pickups(pickups,false,true,10)==0)
local catalog={LOADOUT={SLOTS=9,MAX_SLOTS=11,LOCKED="Clear"},ALL_TOOLS={}}
for _,id in ipairs({"Recon","Medics","Evac","Rooftop","Strike","Fort","Gate","Wall","Clear"})do table.insert(catalog.ALL_TOOLS,{id=id})end
table.insert(catalog.ALL_TOOLS,{id="Tent",unlock=600});table.insert(catalog.ALL_TOOLS,{id="Ghosts",crate="common"})
local kit=Model.loadout(catalog,{unlocks={},upgrades={}},false,{})
check(#kit==9 and kit[#kit]=="Clear")
check(table.find(kit,"Tent")==nil and table.find(kit,"Ghosts")==nil)
kit=Model.loadout(catalog,{unlocks={Tent=true,Ghosts=true},upgrades={toolSlot=1}},true,{})
check(#kit==11 and table.find(kit,"Tent")~=nil and table.find(kit,"Ghosts")~=nil)
kit=Model.loadout(catalog,{unlocks={},upgrades={}},false,{Clear=true,Evac=true,Rooftop=true})
check(table.find(kit,"Clear")==nil and table.find(kit,"Evac")==nil and table.find(kit,"Rooftop")==nil)
local bombing={time=10,city=city,agents={},tents={},depots={}}
local bomb={radius=46,delay=1.5,flyTime=2,minLength=60,maxLength=340}
for i=1,10 do table.insert(bombing.agents,{kind="Zombie",x=450+i*3,y=450,vx=0,vy=0})end
local path=Model.ordnance(bombing,bomb,5)
check(path and path.hits==10 and path.risk==0)
table.insert(bombing.agents,{kind="Soldier",main=true,x=465,y=450})
check(Model.ordnance(bombing,bomb,5)==nil)
table.remove(bombing.agents)
for i=1,10 do table.insert(bombing.agents,human(450+i*3,450))end
check(Model.ordnance(bombing,bomb,0)==nil)
bombing.agents={{kind="Zombie",special="weeper",x=450,y=450}}
check(Model.ordnance(bombing,bomb,0)~=nil)
bombing.agents[1].hidden=true;check(Model.ordnance(bombing,bomb,0)==nil)
local clinical={time=10,agents={{kind="Human",x=100,y=100,infected=true,revealUntil=20}}}
check(Model.medicTarget(clinical,{x=0,y=0})==clinical.agents[1])
clinical.agents[1].patientZero=true;check(Model.medicTarget(clinical,{x=0,y=0})==nil)
clinical.agents[1].patientZero=nil
table.insert(clinical.agents,{kind="Zombie",x=120,y=100})
check(Model.medicTarget(clinical,{x=0,y=0})==nil)
clinical.agents[2].hidden=true;check(Model.medicTarget(clinical,{x=0,y=0})~=nil)
clinical.time=21;check(Model.medicTarget(clinical,{x=0,y=0})==nil)
local latent={time=10,agents={{x=100,y=100,kind="Human",infected=true,revealUntil=0}}}
check(Model.treatment(latent,70,30,true).count==1)
check(Model.medicTarget(latent,{x=0,y=0},true)==latent.agents[1])
latent.agents[1].patientZero=true;check(Model.treatment(latent,70,30,true)==nil)
check(Model.sourceIntel(latent,175).x==100)
latent.recons={{x=100,y=100,r=175}};check(Model.sourceIntel(latent,175)==nil)
latent.recons[1].dead=true;check(Model.sourceIntel(latent,175)~=nil)
latent.agents[1]={x=400,y=400,kind="Zombie",hidden=true}
check(Model.sourceIntel(latent,175).x==400)
latent.agents[1].hidden=false;check(Model.sourceIntel(latent,175)==nil)
print("Last Stand planning checks passed:",passed)
