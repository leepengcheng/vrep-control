--@@机器人核心类

local const=require("const")
local robot = {}


function robot.new(self, param)
    return setmetatable(robot, {__index = param.robot})
end

robot.applyJoints = function(self, values)
    for i = 1, self.joint.num do
        -- sim.setJointTargetPosition(jointHandles[i],values[i])
        sim.setJointPosition(self.joint.handles[i], values[i])
    end
end

robot.setGripper=function(self,g)
    self.gripper=g
end

--获取当前构型
robot.getConfig = function(self)
    local configs = {-1, -1, -1, -1, -1, -1, -1}
    for i = 1, self.joint.num do
        configs[i] = sim.getJointPosition(self.joint.handles[i])
    end
    return configs
end

--获取末端tip的当前位姿
robot.getTipMatrix=function(self)
    return sim.getObjectMatrix(self.ik.tipHandle,self.robotHandle)
end


--设置当前构型
robot.setConfig = function(self, config)
    for i = 1, self.joint.num do
        sim.setJointPosition(self.joint.handles[i], config[i])
    end
end


robot.getCollisionPairs = function(self)
    local p = {
        self.collisions.robotColHandle,
        self.collisions.objectColHandle
    }
    return p
end

--计算2个目标构型之间的距离(构型空间),sqrt(dx**2)
--@config1:构型1
--@config2:构型2
--@return:2个构型之间的伪距离
robot.getConfigDistance = function(self, config1, config2)
    local d = 0
    for i = 1, self.joint.num do
        --每个关节*对应的权值
        local dx = (config1[i] - config2[i]) * self.metric[i]
        d = d + dx * dx
    end
    return math.sqrt(d)
end

-- 计算整条路径的能量距离(构型空间),用于选择规划出的最短路径
-- @path:规划出的路径(关节空间/构型空间)
-- @return:路径的伪长度
robot.getPathLength = function(self, path)
    local d = 0
    local l = self.joint.num
    local pc = #path / self.joint.num
    for i = 1, pc - 1 do
        local config1 = {
            path[(i - 1) * l + 1],
            path[(i - 1) * l + 2],
            path[(i - 1) * l + 3],
            path[(i - 1) * l + 4],
            path[(i - 1) * l + 5],
            path[(i - 1) * l + 6],
            path[(i - 1) * l + 7]
        }
        local config2 = {
            path[i * l + 1],
            path[i * l + 2],
            path[i * l + 3],
            path[i * l + 4],
            path[i * l + 5],
            path[i * l + 6],
            path[i * l + 7]
        }
        d = d + self:getConfigDistance(config1, config2)
    end
    return d
end

--返回每个构型距离依次递增table,用于RML速度映射
--小等于规划的目标构型的数目，此处为200
--@path:规划出的关节控制的路径点,size=joint_size*config_size
robot.getPathLengthTable = function(self, path)
    local d = 0
    local l = self.joint.num
    local pc = #path / self.joint.num
    local retLengths = {0}
    for i = 1, pc - 1, 1 do
        local config1 = {
            path[(i - 1) * l + 1],
            path[(i - 1) * l + 2],
            path[(i - 1) * l + 3],
            path[(i - 1) * l + 4],
            path[(i - 1) * l + 5],
            path[(i - 1) * l + 6],
            path[(i - 1) * l + 7]
        }
        local config2 = {
            path[i * l + 1],
            path[i * l + 2],
            path[i * l + 3],
            path[i * l + 4],
            path[i * l + 5],
            path[i * l + 6],
            path[i * l + 7]
        }
        d = d + self:getConfigDistance(config1, config2)
        retLengths[i + 1] = d
    end
    return retLengths
end

-- 搜索TopN无碰撞且满足目标位姿构型
-- @matrix:目标姿态
-- @trialCnt:尝试寻找目标构型的次数
-- @maxConfigs:返回成功构型的最大个数
-- @return:cs,返回计算出的目标构型的table，大小为N*6的二维数组,N<=maxConfigs
robot.findTopNCollisionFreeConfigs = function(self, targetMatrix)
    sim.setObjectMatrix(self.ik.targetHandle, -1, targetMatrix) --将目标设置为target
    local cc = self:getConfig()
    local cs = {}
    local l = {}
    for i = 1, self.attemptCount do
        --寻找最多maxConfigs个目标构型
        -- local c = self:findCollisionFreeConfig(targetMatrix)
        local c =
            sim.getConfigForTipPose(
            self.ik.pinvHandle,
            self.joint.handles,
            0.65,
            100,
            nil,
            self:getCollisionPairs(),
            nil,
            self.joint.limitsL,
            self.joint.ranges
        )
        -----------------打印消息----------------
        if c then
            sim.addStatusbarMessage("第 " .. i .. " 次搜索目标构型: Success")
        else
            sim.addStatusbarMessage("第 " .. i .. " 次搜索目标构型: Falied")
        end
        ---------------------------------------
        if c then
            --计算构型的能量距离(构型空间)
            local dist = self:getConfigDistance(cc, c)
            local same = false
            -- 有可能获得的构型相同，为避免返回多个相同的目标构型
            -- 先检查构型能量，然后检查每个关节运动角度的偏差是否大于阈值
            for j = 1, #l, 1 do
                if math.abs(l[j] - dist) < 0.001 then
                    same = true
                    for k = 1, self.joint.num do
                        if math.abs(cs[j][k] - c[k]) > 0.01 then
                            same = false
                            break
                        end
                    end
                end
                if same then
                    break
                end
            end
            if not same then
                cs[#cs + 1] = c
                l[#l + 1] = dist
            end
        end
        if #l >= self.maxConfigs then
            break
        end
    end
    --如果无可以的构型，则返回空
    if #cs == 0 then
        cs = nil
    end
    return cs
end

--计算起始构型到目标构型的路径，每个目标构型计算cnt次
--返回最短的路径以及长度(构型空间的能量距离)
--部分关节的运动范围过大,例如+-10'000,将会导致搜索空间过大/速度过慢/效率降低,所以限制关节的运动范围
--@startConfig:初始构型
--@goalConfigs:目标构型

robot.findPath = function(self, startConfig, goalConfigs)
    local task = simOMPL.createTask("task") --创建任务
    simOMPL.setAlgorithm(task, self.algoOMPL) --设置算法
    simOMPL.setVerboseLevel(task, 0) --设置消息级别
    local jSpaces = {}
    for i = 1, self.joint.num do
        local proj = i
        if i > 3 then
            proj = 0
        end
        --设置关节状态空间：名称，类型，关节句柄table,关节下限table,关节上限table,是否用于计算关节映射table(为true时)：1,2,3关节映射，其他几个关节不映射
        --weight:默认为1.0，用于计算不同构型之间的距离(在后面自定义)。返回值为该关节空间的句柄
        jSpaces[#jSpaces + 1] =
            simOMPL.createStateSpace(
            "j_space" .. i,
            simOMPL.StateSpaceType.joint_position,
            self.joint.handles[i],
            {self.joint.limitsL[i]},
            {self.joint.limitsH[i]},
            proj
        )
    end
    simOMPL.setStateSpace(task, jSpaces)
    -- simOMPL.setCollisionPairs(task, collisionPairs) --设置碰撞对
    simOMPL.setStartState(task, startConfig) --设置初始构型
    simOMPL.setGoalState(task, goalConfigs[1]) --设置目标构型
    for i = 2, #goalConfigs, 1 do
        simOMPL.addGoalState(task, goalConfigs[i]) --添加其他的目标构型
    end
    local path = nil
    local l = math.huge
    --    forbidThreadSwitches(true)
    --计算planningTime次目标构型
    for i = 1, self.configPlanAttempts do
        -- 等价于:
        -- simExtOMPL_setup(task)
        -- if simExtOMPL_solve(task, maxTime) then
        --     simExtOMPL_simplifyPath(task, maxSimplificationTime)
        --     simExtOMPL_interpolatePath(task, stateCnt)
        --     result,path = simExtOMPL_getPath(task)
        -- end
        --参数：maxSimplificationTime,用于简化路径的时间，-1表示默认；stateCnt：返回的差值路径点(构型)数量
        local configCountOMPL=self:getOMPLPathPointCount(startConfig, goalConfigs,self.stepOMPL)
        -- print("configCountOMPL:.."..configCountOMPL)
        local res, _path = simOMPL.compute(task, self.singlePlanTime, -1, configCountOMPL)
        if res and _path then
            local _l = self:getPathLength(_path)
            if _l < l then
                l = _l
                path = _path
            end
        end
    end
    --    forbidThreadSwitches(false)
    simOMPL.destroyTask(task)
    --清除任务
    return path, l
end

robot.findShortestPath = function(self, startConfig, goalConfigs)
    -- 计算起始构型到目标构型的路径，每个目标构型计算cnt次
    --返回最短的路径以及长度(构型空间的能量距离)
    --其中onepath 为N*6=1200,即路径上200个构型*6个关节的角度
    local onePath, onePathLength = self:findPath(startConfig, goalConfigs)
    if onePath then
        --如果不计算轨迹，则不需要计算PathLengthTable(节省计算资源))
        if self.isCalculateTraj then
            return onePath, self:getPathLengthTable(onePath)
        else 
            return onePath,nil
        end
    end
    sim.addStatusbarMessage("寻找最短路径失败")
    return nil, nil
end

--路径规划
robot.getOMPLPlaningPath = function(self, targetMatrix)
    -- path,lengths=common:loadPath(rdsHandle,'jacoPath_1')     --加载保存的路径
    --进行可用构型搜索
    sim.addStatusbarMessage("开始搜索可用目标构型...")

    local targetConfigs = self:findTopNCollisionFreeConfigs(targetMatrix)

    --如果没有找到可用的目标构型则返回
    if targetConfigs == nil then
        sim.addStatusbarMessage("未搜索到可用的目标构型，无法进行路径规划")
        return nil, nil
    end
    sim.addStatusbarMessage("搜索到 " .. #targetConfigs .. " 个可用的目标构型")
    sim.addStatusbarMessage("开始进行路径规划")
    --计算路径，返回200个构型*6个关节的角度值，200个构型对应的关节距离累加
    local path, lengths = self:findShortestPath(self:getConfig(), targetConfigs)
    return path, lengths
end

robot.getJointPosDifference = function(self, startValue, goalValue, isRevolute)
    local dx = goalValue - startValue
    if (isRevolute) then
        if (dx >= 0) then
            dx = math.mod(dx + math.pi, 2 * math.pi) - math.pi
        else
            dx = math.mod(dx - math.pi, 2 * math.pi) + math.pi
        end
    end
    return (dx)
end



robot.execPath = function(self, path)
    local l=#path/self.joint.num
    local jointPos={}
    for i=1,l do
        jointPos={path[(i-1)*7+1], path[(i-1)*7+2], path[(i-1)*7+3], path[(i-1)*7+4], path[(i-1)*7+5], path[(i-1)*7+6], path[(i-1)*7+7]}
        self:applyJoints(jointPos)
    end
    return path
    
end

--将路径转换为带时间参数的轨迹
--@path:计算出的路径:7*200
--@lengths:计算出的lengths
robot.execTrajectory = function(self, path, lengths)
    local dt = self.dt or sim.getSimulationTimeStep()

    -- 1.折算出每个关节最大的速度
    local jointsUpperVelocityLimits = {}
    for j = 1, 7, 1 do
        _, jointsUpperVelocityLimits[j] =
            sim.getObjectFloatParameter(self.joint.handles[j], sim.jointfloatparam_upper_limit)
    end
    local velCorrection = 1

    sim.setThreadSwitchTiming(200)
    while true do
        local posVelAccel = {0, 0, 0}
        local targetPosVel = {lengths[#lengths], 0} --终点的位置和速度
        local pos = 0
        local res = 0
        local previousQ = {path[1], path[2], path[3], path[4], path[5], path[6], path[7]}
        local rMax = 0
        local rmlHandle =
            sim.rmlPos(
            1,
            0.0001,
            -1,
            posVelAccel,
            {self.maxVel * velCorrection, self.maxAcc, self.maxJerk},
            {1},
            targetPosVel
        )
        while res == 0 do
            res, posVelAccel, sync = sim.rmlStep(rmlHandle, dt)
            if (res >= 0) then
                l = posVelAccel[1]
                for i = 1, #lengths - 1, 1 do
                    l1 = lengths[i]
                    l2 = lengths[i + 1]
                    if (l >= l1) and (l <= l2) then
                        t = (l - l1) / (l2 - l1)
                        for j = 1, 7, 1 do
                            q =
                                path[7 * (i - 1) + j] +
                                robot:getJointPosDifference(
                                    path[7 * (i - 1) + j],
                                    path[7 * i + j],
                                    self.joint.types[j] == sim.joint_revolute_subtype
                                ) *
                                    t
                            dq = robot:getJointPosDifference(previousQ[j], q, self.joint.types[j] == sim.joint_revolute_subtype)
                            previousQ[j] = q
                            r = math.abs(dq / dt) / jointsUpperVelocityLimits[j]
                            if (r > rMax) then
                                rMax = r
                            end
                        end
                        break
                    end
                end
            end
        end
        sim.rmlRemove(rmlHandle)
        if rMax > 1.001 then
            velCorrection = velCorrection / rMax
        else
            break
        end
    end
    sim.setThreadSwitchTiming(2)

    -- 2. 执行动作
    posVelAccel = {0, 0, 0}
    targetPosVel = {lengths[#lengths], 0}
    pos = 0
    res = 0
    jointPos = {}
    local rmlHandle =
        sim.rmlPos(
        1,
        0.0001,
        -1,
        posVelAccel,
        {self.maxVel * velCorrection, self.maxAcc, self.maxJerk},
        {1},
        targetPosVel
    )

    --时间化的轨迹
    -- local traj={}
    -- local n=1
    while res == 0 do
        dt = sim.getSimulationTimeStep()
        res, posVelAccel, sync = sim.rmlStep(rmlHandle, dt)
        -- sim.setGraphUserData(ghandle,"rml_pos",posVelAccel[1])
        -- sim.setGraphUserData(ghandle,"rml_speed",posVelAccel[2])
        -- sim.setGraphUserData(ghandle,"rml_acc",posVelAccel[3])
        if (res >= 0) then
            l = posVelAccel[1]
            for i = 1, #lengths - 1, 1 do
                l1 = lengths[i]
                l2 = lengths[i + 1]
                if (l >= l1) and (l <= l2) then
                    t = (l - l1) / (l2 - l1)
                    for j = 1, 7, 1 do
                        jointPos[j] =
                            path[7 * (i - 1) + j] +
                            robot:getJointPosDifference(
                                path[7 * (i - 1) + j],
                                path[7 * i + j],
                                self.joint.types[j] == sim.joint_revolute_subtype
                            ) *
                                t
                    end
                    -- table.insert(traj,jointPos)
                    -- traj[n]=jointPos
                    -- n=n+1
                    self:applyJoints(jointPos)
                    break
                end
            end
        end
        sim.switchThread()
    end
    sim.rmlRemove(rmlHandle)
    return path
end


--绝对移动:不改变目标的姿态
--@objHandle:目标的句柄
--@pos:目标的位置
--@action:末端操作:action.open|action.close|action.none
--@method:路径规划的方法：ik|ompl
robot.moveObjectToAbsTxyz=function(self,objHandle,pos,action,method)
    local euler=sim.getObjectOrientation(objHandle,-1)
    local matrix=sim.buildMatrix(pos,euler)
    local path=self:moveToPoseMatrix(matrix,method)
    self.gripper:openClose(action,self.isCalculateMode)
    return path
end



-- robot.pickPlace=function(self,...)
--     local actions={...}
--     local path={}
--     for i=1,#actions do
--     end

--     return path

-- end


--相对移动
--@objHandle:目标的句柄
--@pos:目标的位置
--@euler:目标的姿态
--@action:末端操作:action.open|action.close|action.none
--@method:路径规划的方法：ik|ompl
robot.moveObjectToRelativeTxyzRxyz=function(self,objHandle,pos,euler,action,method)
    local action=action or const.action.none
    local pos=pos or {0,0,0}
    local euler=euler or {0,0,0}
    local baseMatrix=sim.getObjectMatrix(objHandle,self.robotHandle)
    local matrix=sim.buildMatrix(pos,euler)
    local targetMatrix=sim.multiplyMatrices(baseMatrix,matrix)
    local path=self:moveToPoseMatrix(targetMatrix,method)
    self.gripper:openClose(action,self.isCalculateMode)
    return path
end




robot.moveToPoseMatrix = function(self, targetMatrix,method)
    local count = self.singlePosePlanAttempts or math.huge --maxCount为nil时无限循环
    local method=method or "OMPL"
    local ret={} --返回的轨迹或路径
    for i = 1, count do
        local path, lengths=nil,nil
        if method=="OMPL" then
            path, lengths = self:getOMPLPlaningPath(targetMatrix)
        else
            path, lengths = self:getIKPlaningPath(targetMatrix)
        end
        --如果找到最短路径则保存路径和能量累加值
        if path then
            sim.addStatusbarMessage(method.." :路径规划成功")
            if self.isCalculateTraj then
                ret=self:execTrajectory(path, lengths)
            else
                ret=self:execPath(path)
            end
            return ret
        else
            if method=="OMPL" then
                sim.addStatusbarMessage("OMPL路径规划失败第"..i.."次")
                if i==count then
                    sim.addStatusbarMessage("OMPL路径规划失败,目标无法到达")
                    return ret 
                end
            else
                --ik失败后切换到OMPL
                sim.addStatusbarMessage("IK路径规划失败,切换OMPL路径规划")
                return self:moveToPoseMatrix(targetMatrix,"OMPL")
            end
        end
    end
    return ret
end

--计算规划IK的路径的点的个数
--@startMatrix：起始位置的末端位姿
--@goalMatrix:目标位置的末端位姿
--@scale：table={A,B},平移和旋转的权重系数
--@scale: 步长
robot.getIKPathPointCount=function(self,startMatrix,goalMatrix,pathFactor)
    local A,B,step=pathFactor[1],pathFactor[2],pathFactor[3]
    local axis,angle=sim.getRotationAxis(startMatrix,goalMatrix)
    
    local length=math.sqrt((goalMatrix[4]-startMatrix[4])^2+(goalMatrix[8]-startMatrix[8])^2+(goalMatrix[12]-startMatrix[12])^2)
    local L=A*length+B*angle
    local count=math.max(math.ceil(L/step),2) --最小值为2
    -- print(string.format( "##### %s %s %s %s %s %s",startMatrix[4],startMatrix[8],startMatrix[12],goalMatrix[4],goalMatrix[8],goalMatrix[12]))
    -- print("@@@@@@@@L "..length.." Count "..count)
    return count
end

robot.getOMPLPathPointCount=function(self,startConfig,goalConfigs,step)
    local L=0
    local n=#goalConfigs
    for i=1,n do
        L=L+self:getConfigDistance(startConfig,goalConfigs[i])
    end
    local count=math.max(math.ceil(L/n/step),2) --最小值为2
    return count
end

robot.forbidThreadSwitches = function(self, forbid)
    if forbid then
        self.forbidLevel = self.forbidLevel + 1
        if self.forbidLevel == 1 then
            sim.setThreadAutomaticSwitch(false)
        end
    else
        self.forbidLevel = self.forbidLevel - 1
        if self.forbidLevel == 0 then
            sim.setThreadAutomaticSwitch(true)
        end
    end
end

robot.getIKPlaningPath = function(self,targetMatrix)
    --生成从当前构型到目标位姿的、线性的、无碰撞的构型
    local config = self:getConfig()
    local tipMatrix=self:getTipMatrix()
    self:forbidThreadSwitches(true)
    -- self:setConfig(config)
    sim.setObjectMatrix(self.ik.targetHandle, -1, targetMatrix)
    local coll = self:getCollisionPairs()
    if self.ik.ignoreCollisions then
        coll = nil
    end
    local configCountIK=self:getIKPathPointCount(tipMatrix,targetMatrix,self.ik.pathFactor)
    local c = sim.generateIkPath(self.ik.pinvHandle, self.joint.handles, configCountIK, coll)
    --失败后换成dls
    if c==nil then
        c = sim.generateIkPath(self.ik.dlsHandle, self.joint.handles, configCountIK, coll)
    end
    self:setConfig(config)
    self:forbidThreadSwitches(false)
    if c then
        if self.isCalculateTraj then
            return c, self:getPathLengthTable(c)
        else
            return c, nil
        end
    else
        return nil, nil
    end
    
end

return robot