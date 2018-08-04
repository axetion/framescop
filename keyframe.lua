local ctlStateEnum = require('controller_state')

local Keyframe = {}
Keyframe.__index = Keyframe

Keyframe.list = KEYFRAME_LIST_GLOBAL
Keyframe.editMode = 0

Keyframe.new = function(film,frameIndex,state,data)
    if data.author == nil then
        data.author = CURRENT_AUTHOR
    end

    if state ~= 0 then
        printst('Keyframe created')
    end

    local self = {}
    setmetatable(self, Keyframe)

    if FileMgr.autosaveCount ~= -1 then
        FileMgr.autosaveCount = FileMgr.autosaveCount + 1
        -- Every few created keyframes, save.
        if FileMgr.autosaveCount > 10 then
            FileMgr.autosaveCount = 0
            FileMgr.saveAs('autosave')
        end
    end

    self.film = film

    -- Far right bit is the isKeyFrame flag.
    self.state = bit.bor(state,1)
    self.author = data.author

    -- Merge with that keyframe
    if Keyframe.list[frameIndex] then
        print('warning: overwriting frame at ' .. frameIndex)
    end

    Keyframe.list[frameIndex] = self

    return self
end

Keyframe.drawUI = function(film)
    Keyframe.x = love.graphics.getWidth() - 256 - 4
    Keyframe.y = love.graphics.getHeight() - 128 - 32

    local buttonRadius = 16
    local x = Keyframe.x+buttonRadius
    local y = Keyframe.y+buttonRadius

    local state = Keyframe.getStateAtTime(film.playhead)

    love.graphics.setColor(0,0,0,0.25)
    love.graphics.rectangle('fill',Keyframe.x-16,Keyframe.y-16,256,128)
    -- State's far right bit will be 1 if this is an actual keyframe and not just fetching most recent
    if state % 2 == 1 then
        love.graphics.setColor(1,1,1,1)
        love.graphics.print('author: ' .. Keyframe.getCurrentKeyframe(film).author,Keyframe.x-16,Keyframe.y-32)
        love.graphics.rectangle('line',Keyframe.x-16,Keyframe.y-16,256,128)
    end

    love.graphics.setColor(1,1,1)

    -- Up/Down/Left/Right are all just rotated V's. I'm lazy like that.
    local dis = 32
    Keyframe.drawButton('up',x+dis,y)
    Keyframe.drawButton('down',x+dis,y+dis*2)
    Keyframe.drawButton('left',x,y+dis)
    Keyframe.drawButton('right',x+dis*2,y+dis)
    
    dis = 32
    Keyframe.drawButton('x',x+128+dis,y+dis*2)
    Keyframe.drawButton('triangle',x+128+dis,y)
    Keyframe.drawButton('square',x+128,y+dis)
    Keyframe.drawButton('circle',x+128+dis*2,y+dis)

    Keyframe.drawButton('select',x+128-64+16,y)
    Keyframe.drawButton('start',x+128-16,y)
    love.graphics.setColor(1,1,1)
end

function Keyframe.drawButton(buttonName,x,y)
    local r = 16

    if Keyframe.isButtonCurrentlySet(buttonName) then
        love.graphics.setColor(.5,.5,.5)
        love.graphics.circle('line',x,y,r)
    end
    
    love.graphics.setColor(1,1,1)
    if isDirection(buttonName) then
        local angles = {}
        angles['up'] = math.pi
        angles['down'] = 0
        angles['left'] = math.pi/2
        angles['right'] = 0-math.pi/2
    
        local angle = 0
        if angles[buttonName] then
            angle = angles[buttonName]
        end

        drawButtonGraphic('direction',x,y,angle)
        --love.graphics.print('V',x,y,angle,1,1,4,8)
    end

    -- detect hovers
    local mx,my = love.mouse.getPosition()
    if mx > x - r and my > y - r then
        if mx < x + r and my < y + r then
            if not Keyframe.isButtonCurrentlySet(buttonName) then
                love.graphics.setColor(.25,.25,.25)
            end
            love.graphics.circle('line',x,y,r)
            CURRENT_MOUSEOVER_TARGET = buttonName
        end
    end

    love.graphics.setColor(1,1,1)

    if isFaceButton(buttonName) then
        drawButtonGraphic(buttonName,x,y)
    end

    if isStartSelect(buttonName) then
        love.graphics.print(buttonName,x,y,0,1,1,16,8)
    end

    love.graphics.setColor(1,1,1)

    -- Might want to move this input code somewhere else, I don't like 
    -- random keybinds in the middle of my draw calls.
    if altDown() and (isFaceButton(buttonName) or buttonName == 'start') then
        love.graphics.setColor(1,0,0)
   end

    if ctrlDown() and (isDirection(buttonName) or buttonName == 'select') then
        love.graphics.setColor(1,0,0)
    end

    -- draw outline
    -- love.graphics.circle('line',x,y,r)
end

-- flip one bit at on state enum
-- behavior is weird for more than one bit so one at a time please
Keyframe.flipState = function(self,stateRegister)
    local isOnAlready = bit.band(self.state,stateRegister) > 0
    if isOnAlready then
        self.state = bit.band(self.state,bit.bnot(stateRegister))
    else
        self.state = bit.bor(self.state,stateRegister)
    end
end

-- Returns true if keyframe has that state
-- TODO: we can get much cleaner code if we use this more.
-- currently lots of places that have ugly nested bits functions
Keyframe.hasState = function(self,stateName)
    if not ctlStateEnum[stateName] then
        return false
    end
    return bit.band(ctlStateEnum[stateName],self.state) > 0
end

function Keyframe.isButtonCurrentlySet(buttonName)
    state = Keyframe.getStateAtTime(currentFilm.playhead)
    return bit.band(ctlStateEnum[buttonName],state) > 0
end

Keyframe.addState = function(self,stateName)
    if ctlStateEnum[stateName] then
        self.state = bit.bor(ctlStateEnum[stateName],self.state)
    end
end

Keyframe.getCurrentKeyframe = function(film,forceCreate)
    local kf = Keyframe.list[film.playhead]
    if kf == nil then
        if forceCreate then
            return Keyframe.new(film,film.playhead,Keyframe.getStateAtTime(film.playhead),{data=CURRENT_AUTHOR,notes=''})
        end
        local i = film.playhead
        while i > 0 do
            kf = Keyframe.list[i]
            if kf then
                return kf
            end
            i = i-1
        end
    else
        return kf
    end
end

-- Returns a sorted array of all keyframes
-- Traverses through the entire timeline to get it.
-- O(n) sort for medium-large n, thoughts?
Keyframe.getAll = function(film,realtime)
    list = {}
    for i=1,film.totalFrames do
        if Keyframe.list[i] ~= nil then
            list[#list+1] = Keyframe.list[i]
            Keyframe.list[i].time = i
            if realtime then
                Keyframe.list[i].time = currentFilm:timeString(i)
            end
        end
    end
    return list
end

-- Gets either the current keyframe state or the most recent key frame state
Keyframe.getStateAtTime = function(frameIndex)
    if Keyframe.list[frameIndex] then
        return Keyframe.list[frameIndex].state
    end

    local i = frameIndex
    while i > 0 do
        if Keyframe.list[i] then
            -- Chop off the isKeyFrame bit so we know if this state comes from a keyframe or not
            return bit.band(Keyframe.list[i].state,bit.bnot(ctlStateEnum.isKeyFrame))
        end
        i = i - 1
    end

    return 0
end

return Keyframe