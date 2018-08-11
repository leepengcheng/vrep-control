--控制脚本-多线程：UI
local dir=os.getenv("RDS") --添加工作路径
package.path=string.format( "%s;%s/lib/?.lua",package.path,dir)
local tools=require("tools")
local const=require("const")


---###############自定义函数###############
--加载并保存数据
function loadConfig(self) 
    --init
    simUI.insertComboboxItem(self.ui,const.UI.comboSel,0,"自动")
    simUI.insertComboboxItem(self.ui,const.UI.comboSel,1,"手动")
    --populate data
    local data=self:readInfo(const.SIGNAL.UI_PARAM)
    simUI.setEditValue(self.ui,const.UI.editPath,data.editPath or "")
    simUI.setEditValue(self.ui,const.UI.editTarget,data.editTarget or "")
    simUI.setEditValue(self.ui,const.UI.editIndex,data.editIndex or "0")
    simUI.setEditValue(self.ui,const.UI.editStep,data.editStep or "1")
    simUI.setEditValue(self.ui,const.UI.remoteID,data.remoteID or "162.168.6.90.1.1")
    simUI.setEditValue(self.ui,const.UI.remoteIP,data.remoteIP or "127.0.0.1")
    simUI.setEditValue(self.ui,const.UI.localID,data.localID or "192.168.6.85.1.1")
    simUI.setEditValue(self.ui,const.UI.editWriteAddr,data.editWriteAddr or  "MAIN.traj_path")
    simUI.setEditValue(self.ui,const.UI.editReadAddr,data.editReadAddr or "MAIN.robo_status")
    simUI.setComboboxSelectedIndex(self.ui,const.UI.comboSel,data.comboSel or 0,false)

    --UI position
    local pos=data.position or {290,90}
    -- simUI.setPosition(self.ui,pos[1],pos[2])
end

--保存数据到对象
function saveConfig(self)
    local data={}
    data.comboSel= comboSel or 0
    data.editTarget=simUI.getEditValue(self.ui,const.UI.editTarget)
    data.editPath=simUI.getEditValue(self.ui,const.UI.editPath)
    data.editIndex=simUI.getEditValue(self.ui,const.UI.editIndex)
    data.editStep=simUI.getEditValue(self.ui,const.UI.editStep)
    data.remoteID=simUI.getEditValue(self.ui,const.UI.remoteID)
    data.remoteIP=simUI.getEditValue(self.ui,const.UI.remoteIP)
    data.localID=simUI.getEditValue(self.ui,const.UI.localID)
    data.writeAddr=simUI.getEditValue(self.ui,const.UI.editWriteAddr)
    data.readAddr=simUI.getEditValue(self.ui,const.UI.editReadAddr)

    --ui position
    local x,y=simUI.getPosition(self.ui)
    data.position={x,y}
    tools:writeInfo(const.SIGNAL.UI_PARAM,data)
end


--验证输入的数据
function parsePathFileContent(ui)
    --自主规划路径不需要验证
    local data={}
    if comboSel==0 then
        return data
    end
    local pathStr=simUI.getEditValue(ui,const.UI.editPath)
    if not isFileExist(pathStr) then
        print("请输入正确的文件路径")
        return nil
    else
        f=io.open(pathStr,"r")
        local dataList=string.split(f:read(),"[^%s]+")
        f:close()
        if #dataList~=8 then
            print("错误:轨迹文件每行包含7个轴的数据并用空格分开")
            return nil
        end
    end
    --读入并解析数据点
    local n=1
    for line in io.lines(pathStr) do
        local dataList=string.split(line,"[^%s]+")
        for i=1,7 do
            -- table.insert(data,tonumber(dataList[i]))
            data[n]=tonumber(dataList[i])
            n=n+1
        end
    end
    return data
end

--检查文件是否存在
function isFileExist(name)
    local f=io.open(name,'r')
    if f~=nil then 
         io.close(f)
         return true
    end
    return false
 end


function initUIXml()
    local tab1Xml=string.format([[
        <label style="font:13px;color:rgba(0,0,255,255)" text="路径规划方式" />
        <combobox id="%d" on-change="onComboselChanged" />
        <edit  id="%d" enabled="false" />
        <button id="%d" text="路径文件" enabled="false" on-click="on_openfile_click"/>
        <br />
        <button text="路径规划" on-click="on_plan_click"/>
        <edit  id="%d" /><br />
        <button text="发送路径" on-click="on_traj_new_click"/>
        <button text="开始运动" on-click="on_traj_start_click"/>
        <button text="暂停运动" on-click="on_traj_pause_click"/>
        <button text="停止运动" on-click="on_traj_stop_click"/>
    ]],const.UI.comboSel,const.UI.editPath,const.UI.buttonPath,const.UI.editTarget)
    local tab1=tools:createUiTab(tab1Xml,"主界面","grid")
    ----------------------------------------------------------------------------------------------

    local tab2Xml=string.format([[
    <label style="font:13px;color:rgba(0,0,255,255)" text="远程NetID" />
    <edit  id="%d" />
    <label style="font:13px;color:rgba(0,0,255,255)" text="远程IP " />
    <edit  id="%d"/>
    <label style="font:13px;color:rgba(0,0,255,255)" text="本地NetID" />
    <edit  id="%d" />
    <label style="font:13px;color:rgba(0,0,255,255)" text="数据读取地址" />
    <edit  id="%d"  />
    <label style="font:13px;color:rgba(0,0,255,255)" text="数据写入地址" />
    <edit  id="%d"  />
    <button text="打开ADS连接" on-click="on_ads_init_click"/>
    <button text="关闭ADS连接" on-click="on_traj_destroy_click"/>]],const.UI.remoteID,const.UI.remoteIP,const.UI.localID,const.UI.editReadAddr,const.UI.editWriteAddr)
    local tab2=tools:createUiTab(tab2Xml,"ADS设置","form")
--------------------------------------------------------------------
    local tab3Xml=string.format([[
        <label style="font:13px;color:rgba(0,0,255,255)" text="起始位置 " />
        <edit  id="%d"  />
        <label style="font:13px;color:rgba(0,0,255,255)" text="时间间隔 " />
        <edit  id="%d" /> ]],const.UI.editIndex,const.UI.editStep)
    local tab3=tools:createUiTab(tab3Xml,"路径设置","form")
    ---------------------------------------------------------------

    local tab4Xml=string.format([[
        <checkbox style="font:13px;color:rgba(0,0,255,255)" text="关节状态" on-change="on_check_readstatus" id="900" checked="false" />
        <checkbox style="font:13px;color:rgba(0,0,255,255)" text="关节位置" on-change="on_check_readstatus" id="901" checked="false" />
        <label style="font:13px;color:rgba(0,0,255,255)" text="起始位置 " />
        <edit  id="%d"  />
        <label style="font:13px;color:rgba(0,0,255,255)" text="时间间隔 " />
        <edit  id="%d" /> ]],902,903)
    local tab4=tools:createUiTab(tab4Xml,"关节反馈","form")
    ---------------------------------------------------------------

    return tools:createUiFromTabs({tab1,tab2,tab3,tab4})

end


---############## UI 函数 ###############-
function onComboselChanged(ui,id,index)
    comboSel=index
    simUI.setEnabled(ui,const.UI.editPath,comboSel==1)
    simUI.setEnabled(ui,const.UI.buttonPath,comboSel==1)
end





function on_check_readstatus(ui,id,newVal)
    -- READ_ADDR_BACKUP=READ_ADDR_BACKUP or ADS.readAddr
    -- if newVal==2 then
    --     ADS.readAddr=READ_ADDR_BACKUP
    -- else
    --     ADS.readAddr=nil
    -- end
end

function on_openfile_click(ui,id)
    local f=sim.fileDialog(sim.filedlg_type_load,'打开文件','','','路径文件','txt')
    if f then
        simUI.setEditValue(ui,const.UI.editPath,f,true)
        -- ret=sim.msgBox(sim.msgbox_type_info,sim.msgbox_buttons_ok,'File Read Error',"The specified file could not be read.")
        -- sim.msgbox_return_ok
    end
end



function on_plan_click(ui,id)
    local objName=simUI.getEditValue(ui,const.UI.editTarget)
    local posIndex=1
    local msgTable={objName,"new",4}
    local msg=sim.packTable(msgTable)
    simB0.publish(topicPubPlanCmd,msg)
end

function on_traj_new_click(ui,id)
    local index=math.ceil(tonumber(simUI.getEditValue(ui,const.UI.editIndex)))
    local step=math.ceil(tonumber(simUI.getEditValue(ui,const.UI.editStep)))
    local path=parsePathFileContent(ui)
    if  path then
        print(string.format("发送命令:新的路径,路径点数目: %s",#path))
        local msgTable=tools:packTrajData(const.COM.TRAJ_CMD_NEW,path,index,step)
        local msg=sim.packTable(msgTable)
        simB0.publish(topicPubTrajCmd,msg)
    end
end


function on_ads_init_click(ui,id)
        print("正在打开ADS连接")
        local remoteID=simUI.getEditValue(ui,const.UI.remoteID)
        local remoteIP=simUI.getEditValue(ui,const.UI.remoteIP)
        local localID=simUI.getEditValue(ui,const.UI.localID)
        writeAddr=simUI.getEditValue(ui,const.UI.editWriteAddr)
        readAddr=simUI.getEditValue(ui,const.UI.editReadAddr)
        remoteID=tools:parseADSNetID(remoteID) --解析为number table
        localID=tools:parseADSNetID(localID) --解析为number table
        print(readAddr,writeAddr)
        adsHasInit=simADS.create(remoteID,remoteIP,localID)
        print(adsHasInit)
        -- if adsHasInit then
        --     simADS.read(readAddr,0,simADS_handle_open)    --open read Handle
        -- end
        -- if adsHasInit then
        --     simADS.write(writeAddr,{},simADS_handle_open) --open write handle 
        -- end
end
function on_traj_destroy_click(ui,id)
    print("关闭ADS连接")
    if adsHasInit then
        simADS.write(writeAddr,{},simADS_handle_close)  --close write Handle
        simADS.read(readAddr,0,simADS_handle_close)     --close read Handle
        simADS.destory()
        adsHasInit=nil
    end
end



function on_traj_start_click(ui,id)
    print("发送命令:执行运动")
    local msgTable=tools:packTrajData(const.COM.TRAJ_CMD_START)
    local msg=sim.packTable(msgTable)
    simB0.publish(topicPubTrajCmd,msg)
end

function on_traj_pause_click(ui,id)
    print("发送命令:暂停运动")
    local msgTable=tools:packTrajData(const.COM.TRAJ_CMD_PAUSE)
    local msg=sim.packTable(msgTable)
    simB0.publish(topicPubTrajCmd,msg)
end

function on_traj_stop_click(ui,id)
    print("发送命令:停止运动")
    local msgTable=tools:packTrajData(const.COM.TRAJ_CMD_STOP)
    local msg=sim.packTable(msgTable)
    simB0.publish(topicPubTrajCmd,msg)
end
---@@@@@@@@@@@ UI 函数 @@@@@@@@@@@--



----#############运行函数##################---
function sysCall_threadmain()
    local handle=sim.getObjectAssociatedWithScript(sim.handle_self)
    local xml=initUIXml()
    tools:createUi(xml,handle,loadConfig,saveConfig)
    comboSel=0
    --#####BlueZero##################
    tools:initResolverB0()
    nodeUI=simB0.create("uiNode")
    topicPubPlanCmd=simB0.createPublisher(nodeUI,const.TOPICS.PLANCMD)
    topicPubTrajCmd=simB0.createPublisher(nodeUI,const.TOPICS.TRAJCMD)
    simB0.init(nodeUI)


    while sim.getSimulationState()~=sim.simulation_advancing_abouttostop do
        sim.switchThread() -- resume in next simulation step
    end
end


--停止
function sysCall_cleanup()
    if nodeUI then
        simB0.cleanup(nodeUI)
        if topicPubPlanCmd then
            simB0.destroyPublisher(topicPubPlanCmd)
        end
        if topicPubTrajCmd then
            simB0.destroyPublisher(topicPubTrajCmd)
        end
        simB0.destroy(nodeUI)
    end
    tools:destroyUi(true)
end
















