-- function include(absolutePathAndFile)
--     if not __notFirst__ then
--         __notFirst__=true
--         __scriptCodeToRun__=assert(loadfile(absolutePathAndFile))
--     end
--     if __scriptCodeToRun__ then
--         __scriptCodeToRun__()
--     end
-- end
-- include('/media/zen/workspace/GitWorkSpace/vrep-control/lua/RDS_01.lua')

-- This is a threaded script, and is just an example!

sim.includeAbs('D:/MyGit/lpc-robot/lua/rds/common.lua')

local pick={
        id="pick",
        grasp_pose={0.5,0.5,0.1,0,0,0,1},
        pre_grasp_posture={
            joint_names={},
            positions={}
        },
        pre_grasp_approach={
            direction={
                vector={1,0,0},
                frame_id=-1
            },
            min_distance=0.2,
            desired_distance=0.4
        },
        post_grasp_retreat={
            direction={
                vector={1,0,0},
                frame_id=-1
            },
            min_distance=0.2,
            desired_distance=0.4
        }
    }




local place={
        id="place",
        place_pose={0.5,0.5,0.1,0,0,0,1},
        post_place_posture={
            joint_names={},
            positions={}
        },
        pre_place_approach={
            direction={
                vector={1,0,0},
                frame_id="world"
            },
            min_distance=0.2,
            desired_distance=0.4
        },
        post_place_retreat={
            direction={
                vector={1,0,0},
                frame_id="world"
            },
            min_distance=0.2,
            desired_distance=0.4
        }
    }


--控制爪子
openGripper=function(open)
    if open then
        sim.setIntegerSignal('RG2_open',1)
    else
        sim.setIntegerSignal('RG2_open',0)
    end
end

--使能/关闭 IK解算
function enableAutoIK(isenable)
    local value=1
    if isenable then
        value=0
    end
    sim.setExplicitHandling(ikPINV,value)
    sim.setExplicitHandling(ikDLS,value)
end


--抓取
pickAction=function(pickPos,pickOrientation,relVel)

    openGripper(true)   --打开爪子
    enableAutoIK(false) --关闭自动IK

    -- --移动到抓取位置(关节控制)
    sim.moveToJointPositions(joints,upperPickupJointPos,jointVelocity*relVel,jointAcceleration*relVel)
    --移动target到tip
    sim.setObjectMatrix(target,-1,sim.getObjectMatrix(tip,-1))

    enableAutoIK(true) --开启自动IK

    --IK解算:抓取预处理
    sim.moveToPosition(target,RDS_01,pickPos,pickOrientation,movementVelocity*relVel,movementAcceleration*relVel)
    openGripper(false) --合并爪子

    sim.wait(1.0)
    
    -- --IK解算:抓取后处理
    sim.moveToPosition(target,RDS_01,{pickPos[1],pickPos[2],pickPos[3]+0.1},pickOrientation,movementVelocity*relVel,movementAcceleration*relVel)
end

--移动到临时放置的位置
moveToIntermediateDropPos=function(relVel)
    enableAutoIK(false)
    --移动到放置的位置
    sim.moveToJointPositions(joints,intermediateDropPos,jointVelocity*relVel,jointAcceleration*relVel)
    m=sim.getObjectMatrix(tip,-1)
    sim.setObjectMatrix(target,-1,m) --移动tip到target
    enableAutoIK(true)
end

placeAction=function(dropPos,dropOrientation,relVel)
    --放置预处理位:z+0.2
    sim.moveToPosition(target,RDS_01,{dropPos[1],dropPos[2],dropPos[3]+0.2},dropOrientation,movementVelocity*relVel,movementAcceleration*relVel)
    -- 放置位
    sim.moveToPosition(target,RDS_01,dropPos,dropOrientation,movementVelocity*relVel,movementAcceleration*relVel)
    openGripper(true)--打开爪子
    sim.wait(1.5)
    --放置退出位:z+0.2
    sim.moveToPosition(target,RDS_01,{dropPos[1],dropPos[2],dropPos[3]+0.2},dropOrientation,movementVelocity*relVel,movementAcceleration*relVel)
end

pickAndPlace=function(pickPos,pickOrientation,dropPos,dropOrientation,useIntermediateDropPos,relVel)
    pickAction(pickPos,pickOrientation,relVel)
    if (useIntermediateDropPos) then
        sim.switchThread() -- Make sure sim.handleIkGroup was already called in this pass
        moveToIntermediateDropPos(relVel)
    end
    placeAction(dropPos,dropOrientation,relVel)
end

function sysCall_threadmain()

    sim.setThreadSwitchTiming(2) -- Default timing for automatic thread switching
    RDS_01=sim.getObjectHandle('RDS_01')
    target=sim.getObjectHandle('RDS_01_target')
    tip=sim.getObjectHandle('RDS_01_tip')
    joints={-1,-1,-1,-1,-1,-1,-1}
    for i=1,7,1 do
        joints[i]=sim.getObjectHandle('j'..i)
    end
    ikPINV=sim.getIkGroupHandle('RDS_IK_PINV')
    ikDLS=sim.getIkGroupHandle('RDS_IK_DLS')

    local pickPos={-0.5,-0.5,0.08}     --抓取的目标位置(不要超过工作空间)    
    local pickOrientation={math.pi,0,0} --抓取的目标姿态
    upperPickupJointPos={0,0,0,0,0,1.5708,0} --中间抓取控制构型
    intermediateDropPos={0,0,0,0,0,-1.5708,0} --中间放置控制构型
    movementVelocity=0.6 --末端速度
    movementAcceleration=2 --末端加速度
    jointVelocity=math.pi*0.6 --关节速度
    jointAcceleration=10 --关节加速度

    local placePos={0.6,0,0.1}
    local placeOrientation={math.pi,0,0}
    pickAndPlace(pickPos,pickOrientation,placePos,placeOrientation,false,1)
end