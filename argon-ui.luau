-- Argon UI: Rayfield-compatible controls with Orion grouping and WindUI/MacLib styling.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Argon = {Flags={},Version="1.3.0",_connections={},_windows={},_loadingConfig=false,_saveToken=0,_destroyed=false,CurrentTheme="Argon"}

local C = {
    Background=Color3.fromRGB(8,10,16), Window=Color3.fromRGB(13,16,24), Sidebar=Color3.fromRGB(10,13,20),
    Surface=Color3.fromRGB(19,23,33), Hover=Color3.fromRGB(24,29,41), Active=Color3.fromRGB(30,34,48),
    Input=Color3.fromRGB(14,18,27), Border=Color3.fromRGB(44,49,65), BorderSoft=Color3.fromRGB(31,36,49),
    Text=Color3.fromRGB(241,243,249), Muted=Color3.fromRGB(150,157,177), Dim=Color3.fromRGB(98,106,128),
    Accent=Color3.fromRGB(153,112,255), AccentLight=Color3.fromRGB(195,170,255), AccentDark=Color3.fromRGB(92,61,184),
    Success=Color3.fromRGB(74,222,162), Warning=Color3.fromRGB(247,190,79), Danger=Color3.fromRGB(255,101,124),
}

Argon.Themes = {
    Argon={},
    Midnight={Background=Color3.fromRGB(6,9,15),Window=Color3.fromRGB(10,14,23),Sidebar=Color3.fromRGB(7,11,18),Surface=Color3.fromRGB(16,22,34),Hover=Color3.fromRGB(21,29,44),Active=Color3.fromRGB(27,36,54),Input=Color3.fromRGB(10,15,25),Border=Color3.fromRGB(42,53,72),BorderSoft=Color3.fromRGB(28,37,52),Text=Color3.fromRGB(238,244,255),Muted=Color3.fromRGB(146,159,181),Dim=Color3.fromRGB(87,101,126),Accent=Color3.fromRGB(88,166,255),AccentLight=Color3.fromRGB(155,205,255),AccentDark=Color3.fromRGB(35,91,180),Success=Color3.fromRGB(76,220,166),Warning=Color3.fromRGB(247,190,79),Danger=Color3.fromRGB(255,101,124)},
    Emerald={Background=Color3.fromRGB(6,12,11),Window=Color3.fromRGB(10,18,17),Sidebar=Color3.fromRGB(7,15,14),Surface=Color3.fromRGB(16,27,25),Hover=Color3.fromRGB(21,35,32),Active=Color3.fromRGB(27,44,40),Input=Color3.fromRGB(10,20,18),Border=Color3.fromRGB(42,66,60),BorderSoft=Color3.fromRGB(28,46,42),Text=Color3.fromRGB(238,249,246),Muted=Color3.fromRGB(145,171,164),Dim=Color3.fromRGB(87,119,111),Accent=Color3.fromRGB(52,211,153),AccentLight=Color3.fromRGB(151,246,211),AccentDark=Color3.fromRGB(15,118,88),Success=Color3.fromRGB(74,222,162),Warning=Color3.fromRGB(247,190,79),Danger=Color3.fromRGB(255,101,124)},
    Rose={Background=Color3.fromRGB(13,7,11),Window=Color3.fromRGB(21,11,18),Sidebar=Color3.fromRGB(17,8,14),Surface=Color3.fromRGB(31,17,27),Hover=Color3.fromRGB(42,22,35),Active=Color3.fromRGB(54,28,45),Input=Color3.fromRGB(24,12,20),Border=Color3.fromRGB(73,42,61),BorderSoft=Color3.fromRGB(50,29,43),Text=Color3.fromRGB(255,239,248),Muted=Color3.fromRGB(188,148,171),Dim=Color3.fromRGB(132,91,115),Accent=Color3.fromRGB(244,114,182),AccentLight=Color3.fromRGB(251,182,220),AccentDark=Color3.fromRGB(190,24,93),Success=Color3.fromRGB(74,222,162),Warning=Color3.fromRGB(247,190,79),Danger=Color3.fromRGB(255,101,124)},
}
Argon.Themes.Argon={}
for key,value in pairs(C) do Argon.Themes.Argon[key]=value end
Argon.Themes.Amethyst={}
for key,value in pairs(C) do Argon.Themes.Amethyst[key]=value end

local ICONS={
    activity={{{3,12},{7,12},{10,4},{14,20},{17,12},{21,12}}},
    swords={{{4,3},{20,19}},{{14,3},{21,3},{21,10}},{{3,14},{10,21}},{{3,21},{7,17}},{{17,21},{21,17}}},
    zap={{{13,2},{4,14},{11,14},{10,22},{20,9},{13,9},{13,2}}},
    move={{{12,3},{12,21}},{{8,7},{12,3},{16,7}},{{8,17},{12,21},{16,17}},{{3,12},{21,12}},{{7,8},{3,12},{7,16}},{{17,8},{21,12},{17,16}}},
    shirt={{{8,4},{4,6},{2,11},{6,13},{6,22},{18,22},{18,13},{22,11},{20,6},{16,4},{14,7},{10,7},{8,4}}},
    pickaxe={{{14,4},{20,10}},{{17,3},{21,7}},{{16,8},{5,19}},{{3,21},{7,17}}},
    ["radio-tower"]={{{12,10},{12,22}},{{8,22},{16,22}},{{9,14},{12,10},{15,14}},{{7,8},{4,11},{4,15},{7,18}},{{17,8},{20,11},{20,15},{17,18}},{{4,5},{1,9},{1,17},{4,21}},{{20,5},{23,9},{23,17},{20,21}}},
    eye={{{2,12},{5,8},{9,6},{12,6},{15,6},{19,8},{22,12},{19,16},{15,18},{12,18},{9,18},{5,16},{2,12}}},
    ["map-pin"]={{{12,22},{7,16},{5,12},{5,8},{7,4},{10,2},{14,2},{17,4},{19,8},{19,12},{17,16},{12,22}},{{9,9},{10,7},{12,6},{14,7},{15,9},{14,11},{12,12},{10,11},{9,9}}},
    settings={{{12,3},{12,6}},{{12,18},{12,21}},{{3,12},{6,12}},{{18,12},{21,12}},{{5.5,5.5},{7.7,7.7}},{{16.3,16.3},{18.5,18.5}},{{18.5,5.5},{16.3,7.7}},{{7.7,16.3},{5.5,18.5}},{{8,12},{9,9},{12,8},{15,9},{16,12},{15,15},{12,16},{9,15},{8,12}}},
    search={{{11,4},{8,4},{5,6},{4,9},{4,12},{6,15},{9,16},{12,16},{15,14},{16,11},{16,8},{14,5},{11,4}},{{15,15},{21,21}}},
    ["chevron-down"]={{{6,9},{12,15},{18,9}}},
    users={{{8,11},{6,9},{6,6},{8,4},{11,4},{13,6},{13,9},{11,11},{8,11}},{{3,20},{3,17},{5,14},{8,13},{11,13},{14,14},{16,17},{16,20}},{{16,11},{18,10},{19,8},{19,6},{18,4},{16,3}},{{17,13},{20,14},{22,17},{22,20}}},
    keyboard={{{3,6},{21,6},{21,18},{3,18},{3,6}},{{6,10},{7,10}},{{10,10},{11,10}},{{14,10},{15,10}},{{18,10},{19,10}},{{6,14},{8,14}},{{11,14},{17,14}}},
    loader={{{12,2},{12,5}},{{19.1,4.9},{17,7}},{{22,12},{19,12}},{{19.1,19.1},{17,17}},{{12,22},{12,19}},{{4.9,19.1},{7,17}},{{2,12},{5,12}},{{4.9,4.9},{7,7}}},
}

local function safeCall(callback,...)
    if type(callback)~="function" then return end
    local ok,err=pcall(callback,...)
    if not ok then warn("[Argon UI] Callback error: "..tostring(err)) end
end

local function connect(signal,callback)
    local connection=signal:Connect(callback)
    table.insert(Argon._connections,connection)
    return connection
end

local function create(className,props)
    local object=Instance.new(className)
    for property,value in pairs(props or {}) do if property~="Parent" then object[property]=value end end
    if props and props.Parent then object.Parent=props.Parent end
    return object
end

local function corner(parent,radius)
    return create("UICorner",{CornerRadius=UDim.new(0,radius or 10),Parent=parent})
end

local function stroke(parent,color,transparency,thickness)
    return create("UIStroke",{Color=color or C.Border,Transparency=transparency or 0,Thickness=thickness or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Parent=parent})
end

local function padding(parent,left,right,top,bottom)
    return create("UIPadding",{PaddingLeft=UDim.new(0,left or 0),PaddingRight=UDim.new(0,right or left or 0),PaddingTop=UDim.new(0,top or 0),PaddingBottom=UDim.new(0,bottom or top or 0),Parent=parent})
end

local function gradient(parent,first,second,rotation)
    return create("UIGradient",{Color=ColorSequence.new(first,second),Rotation=rotation or 0,Parent=parent})
end

local function iconLine(parent,firstPoint,secondPoint,color,thickness)
    local delta=Vector2.new(secondPoint[1]-firstPoint[1],secondPoint[2]-firstPoint[2])
    local center=Vector2.new((firstPoint[1]+secondPoint[1])/2,(firstPoint[2]+secondPoint[2])/2)
    local line=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=color,BorderSizePixel=0,Position=UDim2.fromScale(center.X/24,center.Y/24),Rotation=math.deg(math.atan2(delta.Y,delta.X)),Size=UDim2.new(math.sqrt(delta.X*delta.X+delta.Y*delta.Y)/24,0,0,thickness or 1.7),Parent=parent})
    corner(line,2)
    return line
end

local function drawIcon(parent,name,color,size)
    local iconSize=size or 20
    local holder=create("Frame",{Name="LucideIcon",AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(iconSize,iconSize),Parent=parent})
    for _,polyline in ipairs(ICONS[tostring(name)] or ICONS.activity) do
        for index=1,#polyline-1 do iconLine(holder,polyline[index],polyline[index+1],color,2.05) end
        for _,point in ipairs(polyline) do
            local cap=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=color,BorderSizePixel=0,Position=UDim2.fromScale(point[1]/24,point[2]/24),Size=UDim2.fromOffset(2.05,2.05),Parent=holder}) corner(cap,3)
        end
    end
    return holder
end

local function recolorIcon(holder,color)
    if not holder then return end
    for _,child in ipairs(holder:GetChildren()) do if child:IsA("Frame") then child.BackgroundColor3=color end end
end

local function mountLogo(parent,size,logoValue,zIndex)
    local holder=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,ClipsDescendants=true,Size=UDim2.fromOffset(size,size),ZIndex=zIndex or 1,Parent=parent})
    corner(holder,math.floor(size*.29)) gradient(holder,C.AccentLight,C.AccentDark,135)
    local image=create("ImageLabel",{AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.72,.72),ScaleType=Enum.ScaleType.Fit,Visible=false,ZIndex=(zIndex or 1)+1,Parent=holder})
    local mark=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.7,.7),ZIndex=(zIndex or 1)+1,Parent=holder})
    iconLine(mark,{5,19},{12,3},Color3.new(1,1,1),math.max(2,size*.075))
    iconLine(mark,{12,3},{19,19},Color3.new(1,1,1),math.max(2,size*.075))
    iconLine(mark,{8,14},{16,14},Color3.new(1,1,1),math.max(2,size*.075))
    local function setLogo(value)
        local source=tostring(value or "")
        if tonumber(value) then source="rbxassetid://"..tostring(value) end
        local custom=source:match("^rbxassetid://") or source:match("^rbxthumb://")
        image.Image=custom and source or "" image.Visible=custom and true or false mark.Visible=not custom
    end
    setLogo(logoValue)
    return holder,setLogo
end

local function tween(object,duration,props,style,direction)
    local animation=TweenService:Create(object,TweenInfo.new(duration or .18,style or Enum.EasingStyle.Quart,direction or Enum.EasingDirection.Out),props)
    animation:Play()
    return animation
end

local function text(parent,value,size,color,font,props)
    local label=create("TextLabel",{BackgroundTransparency=1,Text=value or "",TextColor3=color or C.Text,TextSize=size or 14,Font=font or Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,Parent=parent})
    for property,setting in pairs(props or {}) do label[property]=setting end
    return label
end

local function bindCanvas(scroller,layout,extra)
    local function update() scroller.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+(extra or 0)) end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"),update)
    update()
end

local function resolveParent()
    local parent
    pcall(function() if gethui then parent=gethui() end end)
    return parent or CoreGui
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,nested in pairs(value) do result[key]=copy(nested) end
    return result
end

local function remapColor(value,oldTheme,newTheme)
    for key,oldColor in pairs(oldTheme) do
        if typeof(oldColor)=="Color3" and value==oldColor and typeof(newTheme[key])=="Color3" then return newTheme[key] end
    end
    return value
end

function Argon:AddTheme(name,palette)
    assert(type(name)=="string" and name~="","Theme name must be a non-empty string")
    assert(type(palette)=="table","Theme palette must be a table")
    local merged=copy(self.Themes.Argon)
    for key,value in pairs(palette) do if typeof(value)=="Color3" then merged[key]=value end end
    self.Themes[name]=merged
    return merged
end

function Argon:GetThemes()
    local names={}
    for name in pairs(self.Themes) do table.insert(names,name) end
    table.sort(names)
    return names
end

function Argon:SetTheme(name)
    local nextTheme=type(name)=="table" and name or self.Themes[tostring(name)]
    if not nextTheme then return false,"Unknown theme: "..tostring(name) end
    local oldTheme=copy(C)
    for _,window in ipairs(self._windows) do
        if window.ScreenGui and window.ScreenGui.Parent then
            for _,object in ipairs(window.ScreenGui:GetDescendants()) do
                if object:IsA("UIGradient") then
                    local points={}
                    for _,point in ipairs(object.Color.Keypoints) do table.insert(points,ColorSequenceKeypoint.new(point.Time,remapColor(point.Value,oldTheme,nextTheme))) end
                    object.Color=ColorSequence.new(points)
                else
                    for _,property in ipairs({"BackgroundColor3","BorderColor3","TextColor3","ImageColor3","ScrollBarImageColor3","Color"}) do
                        pcall(function() object[property]=remapColor(object[property],oldTheme,nextTheme) end)
                    end
                end
            end
        end
    end
    for key,value in pairs(nextTheme) do if typeof(value)=="Color3" then C[key]=value end end
    self.CurrentTheme=type(name)=="string" and name or "Custom"
    return true
end

local function contains(list,value)
    for _,entry in ipairs(list) do if entry==value then return true end end
    return false
end

local function keyName(value)
    if typeof(value)=="EnumItem" then return value.Name end
    local name=tostring(value or "None"):gsub("Enum.KeyCode.","")
    return (name=="" or name=="Unknown") and "None" or name
end

local function configPath()
    local config=Argon._configuration
    if not config or not config.Enabled then return nil end
    local folder=config.FolderName or "ArgonUtility"
    local file=config.FileName or "Argon"
    if not file:match("%.rfld$") then file=file..".rfld" end
    return folder.."/"..file,folder
end

local function scheduleSave()
    if Argon._loadingConfig or Argon._destroyed or not configPath() then return end
    Argon._saveToken+=1
    local token=Argon._saveToken
    task.delay(.35,function() if token==Argon._saveToken and not Argon._destroyed then Argon:SaveConfiguration() end end)
end

local function hover(button,normal,over)
    connect(button.MouseEnter,function() tween(button,.14,{BackgroundColor3=over or C.Hover}) end)
    connect(button.MouseLeave,function() tween(button,.18,{BackgroundColor3=normal or C.Surface}) end)
end

local function registerFlag(flag,element)
    if flag and flag~="" then element.Flag=flag Argon.Flags[flag]=element end
end

local function changed(element)
    if element and element._stroke then
        tween(element._stroke,.12,{Color=C.Accent,Transparency=.12})
        task.delay(.25,function() if element._stroke and element._stroke.Parent then tween(element._stroke,.3,{Color=C.BorderSoft,Transparency=.2}) end end)
    end
    scheduleSave()
end

function Argon:SaveConfiguration()
    local path,folder=configPath()
    if not path or not writefile then return false end
    local data={}
    for flag,element in pairs(self.Flags) do
        if element.Type=="Dropdown" then data[flag]=copy(element.CurrentOption)
        elseif element.Type=="Keybind" then data[flag]=keyName(element.CurrentKeybind or element.CurrentValue)
        elseif element.Type=="ColorPicker" and typeof(element.CurrentValue)=="Color3" then data[flag]={__argonColor=true,R=element.CurrentValue.R,G=element.CurrentValue.G,B=element.CurrentValue.B}
        else data[flag]=copy(element.CurrentValue) end
    end
    return pcall(function()
        if folder and makefolder then pcall(makefolder,folder) end
        writefile(path,HttpService:JSONEncode(data))
    end)
end

function Argon:LoadConfiguration()
    local path=configPath()
    if not path or not readfile or not isfile or not isfile(path) then return false end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not ok or type(data)~="table" then return false end
    self._loadingConfig=true
    for flag,value in pairs(data) do
        local element=self.Flags[flag]
        if type(value)=="table" and value.__argonColor then value=Color3.new(tonumber(value.R) or 0,tonumber(value.G) or 0,tonumber(value.B) or 0) end
        if element and element.Set then pcall(function() element:Set(value) end) end
    end
    self._loadingConfig=false
    return true
end

function Argon:Destroy()
    if self._destroyed then return end
    pcall(function() self:SaveConfiguration() end)
    self._destroyed=true
    for _,connection in ipairs(self._connections) do pcall(function() connection:Disconnect() end) end
    for _,window in ipairs(self._windows) do pcall(function() window.ScreenGui:Destroy() end) end
    table.clear(self._connections) table.clear(self._windows) table.clear(self.Flags)
end

function Argon:Notify(options)
    options=options or {}
    local window=self._windows[#self._windows]
    if not window then return end
    local titleValue=tostring(options.Title or "Notification")
    local body=tostring(options.Content or options.Description or "")
    local duration=tonumber(options.Duration) or 4
    local accent=C.Accent
    local lower=titleValue:lower()
    if lower:find("error") or lower:find("failed") then accent=C.Danger
    elseif lower:find("warn") or lower:find("wait") then accent=C.Warning
    elseif lower:find("success") or lower:find("complete") then accent=C.Success end
    local toast=create("Frame",{BackgroundColor3=C.Window,BackgroundTransparency=.03,BorderSizePixel=0,Size=UDim2.fromOffset(338,0),ClipsDescendants=true,ZIndex=100,Parent=window.Notifications})
    corner(toast,13) stroke(toast,C.Border,.12,1)
    local bar=create("Frame",{BackgroundColor3=accent,BorderSizePixel=0,Size=UDim2.fromOffset(3,86),ZIndex=101,Parent=toast}) corner(bar,3)
    local icon=create("Frame",{BackgroundColor3=accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.fromOffset(15,16),Size=UDim2.fromOffset(34,34),ZIndex=101,Parent=toast}) corner(icon,10)
    local toastIcon=drawIcon(icon,"activity",accent) toastIcon.Size=UDim2.fromOffset(17,17)
    text(toast,titleValue,13,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(60,13),Size=UDim2.new(1,-84,0,21),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=101})
    text(toast,body,12,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(60,35),Size=UDim2.new(1,-78,0,39),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=101})
    local close=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Position=UDim2.new(1,-27,0,9),Size=UDim2.fromOffset(18,18),Text="",ZIndex=102,Parent=toast})
    local closeIcon=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(13,13),ZIndex=103,Parent=close})
    iconLine(closeIcon,{4,4},{20,20},C.Dim,1.7) iconLine(closeIcon,{20,4},{4,20},C.Dim,1.7)
    local progress=create("Frame",{BackgroundColor3=accent,BorderSizePixel=0,Position=UDim2.new(0,3,1,-2),Size=UDim2.new(1,-3,0,2),ZIndex=102,Parent=toast})
    local closed=false
    local function dismiss()
        if closed or not toast.Parent then return end
        closed=true tween(toast,.22,{BackgroundTransparency=1,Size=UDim2.fromOffset(338,0)})
        task.delay(.24,function() if toast then toast:Destroy() end end)
    end
    connect(close.MouseButton1Click,dismiss)
    tween(toast,.24,{Size=UDim2.fromOffset(338,86)},Enum.EasingStyle.Back)
    tween(progress,duration,{Size=UDim2.new(0,0,0,2)},Enum.EasingStyle.Linear)
    task.delay(duration,dismiss)
end

function Argon:CreateWindow(options)
    options=options or {}
    self._destroyed=false
    self._configuration=options.ConfigurationSaving or {Enabled=false}
    if options.Theme then self:SetTheme(options.Theme) end
    local guiParent=resolveParent()
    local existing=guiParent:FindFirstChild("Rayfield")
    if existing then pcall(function() existing:Destroy() end) end
    local gui=create("ScreenGui",{Name="Rayfield",DisplayOrder=100,IgnoreGuiInset=false,ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent=guiParent

    local shadow=create("ImageLabel",{BackgroundTransparency=1,Image="rbxassetid://1316045217",ImageColor3=Color3.new(),ImageTransparency=.28,ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(10,10,118,118),AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(1002,682),ZIndex=1,Parent=gui})
    local main=create("Frame",{Name="ArgonWindow",AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Window,BorderSizePixel=0,ClipsDescendants=true,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(980,660),ZIndex=2,Parent=gui})
    corner(main,16) stroke(main,C.Border,.08,1) gradient(main,Color3.fromRGB(17,20,31),Color3.fromRGB(10,12,20),115)
    local glowTop=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Accent,BackgroundTransparency=.91,BorderSizePixel=0,Position=UDim2.new(1,-95,0,35),Size=UDim2.fromOffset(310,310),ZIndex=2,Parent=main}) corner(glowTop,155)
    local glowBottom=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.AccentDark,BackgroundTransparency=.95,BorderSizePixel=0,Position=UDim2.new(.35,0,1,80),Size=UDim2.fromOffset(360,360),ZIndex=2,Parent=main}) corner(glowBottom,180)

    local sidebar=create("Frame",{BackgroundColor3=C.Sidebar,BackgroundTransparency=.06,BorderSizePixel=0,Size=UDim2.new(0,232,1,0),ZIndex=3,Parent=main})
    create("Frame",{BackgroundColor3=C.BorderSoft,BackgroundTransparency=.15,BorderSizePixel=0,Position=UDim2.new(1,-1,0,0),Size=UDim2.new(0,1,1,0),Parent=sidebar})
    local brand,setBrandLogo=mountLogo(sidebar,38,options.Logo,4) brand.Position=UDim2.fromOffset(18,17)
    local brandName=text(sidebar,options.Name or "Argon Utility",15,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(67,17),Size=UDim2.new(1,-82,0,21),TextTruncate=Enum.TextTruncate.AtEnd})
    local brandSub=text(sidebar,"CONTROL CENTER",9,C.Dim,Enum.Font.GothamBold,{Position=UDim2.fromOffset(67,37),Size=UDim2.new(1,-82,0,17)})

    local searchFrame=create("Frame",{BackgroundColor3=C.Input,BorderSizePixel=0,ClipsDescendants=true,Position=UDim2.fromOffset(14,72),Size=UDim2.new(1,-28,0,38),Parent=sidebar})
    corner(searchFrame,10) stroke(searchFrame,C.BorderSoft,.18,1)
    local searchIconHost=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(10,9),Size=UDim2.fromOffset(20,20),Parent=searchFrame})
    drawIcon(searchIconHost,"search",C.Dim,18)
    local search=create("TextBox",{BackgroundTransparency=1,ClearTextOnFocus=false,Font=Enum.Font.Gotham,PlaceholderColor3=C.Dim,PlaceholderText="Search this tab",Position=UDim2.fromOffset(37,0),Size=UDim2.new(1,-70,1,0),Text="",TextColor3=C.Text,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Parent=searchFrame})
    text(searchFrame,"/",10,C.Dim,Enum.Font.GothamBold,{Position=UDim2.new(1,-27,0,9),Size=UDim2.fromOffset(18,20),TextXAlignment=Enum.TextXAlignment.Center})
    local navCaption=text(sidebar,"NAVIGATION",9,C.Dim,Enum.Font.GothamBold,{Position=UDim2.fromOffset(21,122),Size=UDim2.new(1,-42,0,20)})
    local tabList=create("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(12,146),ScrollBarImageColor3=C.Border,ScrollBarThickness=2,Size=UDim2.new(1,-24,1,-205),Parent=sidebar})
    local tabLayout=create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder,Parent=tabList}) bindCanvas(tabList,tabLayout,8)

    local profile=create("Frame",{BackgroundColor3=C.Surface,BackgroundTransparency=.18,BorderSizePixel=0,Position=UDim2.new(0,14,1,-48),Size=UDim2.new(1,-28,0,36),Parent=sidebar}) corner(profile,10)
    local avatar=create("ImageLabel",{BackgroundColor3=C.Active,BorderSizePixel=0,Position=UDim2.fromOffset(5,5),Size=UDim2.fromOffset(26,26),Image="",Parent=profile}) corner(avatar,8)
    pcall(function() avatar.Image=Players:GetUserThumbnailAsync(LocalPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size48x48) end)
    local profileName=text(profile,LocalPlayer and LocalPlayer.DisplayName or "Player",11,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(38,2),Size=UDim2.new(1,-44,0,18),TextTruncate=Enum.TextTruncate.AtEnd})
    local profileState=text(profile,"ARGON ONLINE",8,C.Success,Enum.Font.GothamBold,{Position=UDim2.fromOffset(38,17),Size=UDim2.new(1,-44,0,15)})

    local content=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(232,0),Size=UDim2.new(1,-232,1,0),ZIndex=3,Parent=main})
    local topbar=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,70),Parent=content})
    local eyebrow=text(topbar,"ARGON / DASHBOARD",9,C.AccentLight,Enum.Font.GothamBold,{Position=UDim2.fromOffset(24,14),Size=UDim2.new(1,-150,0,17)})
    local pageTitle=text(topbar,"Dashboard",21,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(24,29),Size=UDim2.new(1,-160,0,29)})
    local sectionsButton=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Surface,BackgroundTransparency=.14,BorderSizePixel=0,Position=UDim2.new(1,-222,0,19),Size=UDim2.fromOffset(86,28),Text="SECTIONS",TextColor3=C.Muted,TextSize=9,Font=Enum.Font.GothamBold,Parent=topbar}) corner(sectionsButton,14) stroke(sectionsButton,C.BorderSoft,.25,1) hover(sectionsButton,C.Surface,C.Hover)
    local status=create("Frame",{BackgroundColor3=C.Surface,BackgroundTransparency=.14,BorderSizePixel=0,Position=UDim2.new(1,-127,0,19),Size=UDim2.fromOffset(75,28),Parent=topbar}) corner(status,14) stroke(status,C.BorderSoft,.25,1)
    local statusGroup=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(42,14),Parent=status})
    local dot=create("Frame",{AnchorPoint=Vector2.new(0,.5),BackgroundColor3=C.Success,BorderSizePixel=0,Position=UDim2.new(0,0,.5,0),Size=UDim2.fromOffset(7,7),Parent=statusGroup}) corner(dot,7)
    text(statusGroup,"LIVE",9,C.Muted,Enum.Font.GothamBold,{Position=UDim2.fromOffset(13,0),Size=UDim2.new(1,-13,1,0),TextXAlignment=Enum.TextXAlignment.Left})
    local hide=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Surface,BackgroundTransparency=.14,BorderSizePixel=0,Position=UDim2.new(1,-43,0,19),Size=UDim2.fromOffset(28,28),Text="–",TextColor3=C.Muted,TextSize=16,Font=Enum.Font.GothamBold,Parent=topbar}) corner(hide,9) stroke(hide,C.BorderSoft,.25,1) hover(hide,C.Surface,C.Hover)
    create("Frame",{BackgroundColor3=C.BorderSoft,BackgroundTransparency=.25,BorderSizePixel=0,Position=UDim2.new(0,24,1,-1),Size=UDim2.new(1,-48,0,1),Parent=topbar})
    local pageHost=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(0,70),Size=UDim2.new(1,0,1,-70),ClipsDescendants=true,Parent=content})

    local notifications=create("Frame",{AnchorPoint=Vector2.new(1,0),BackgroundTransparency=1,Position=UDim2.new(1,(options.PlayerList~=false or options.KeybindList~=false) and -304 or -16,0,16),Size=UDim2.fromOffset(338,500),ZIndex=100,Parent=gui})
    create("UIListLayout",{HorizontalAlignment=Enum.HorizontalAlignment.Right,Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Top,Parent=notifications})

    local window={ScreenGui=gui,Main=main,Shadow=shadow,Sidebar=sidebar,Content=content,TabList=tabList,PageHost=pageHost,Notifications=notifications,Tabs={},ActiveTab=nil,_visible=true,_toggleKey=options.ToggleUIKeybind or Enum.KeyCode.Insert,_userSized=false,_minSize=Vector2.new(560,400),_keybindEntries={},_tabTransitionToken=0}
    table.insert(self._windows,window)
    function window:SetVisibility(value)
        self._visible=value~=false
        if not self._visible and self._dropdownPopup then self._dropdownPopup:Destroy() self._dropdownPopup=nil end
        if not self._visible and self._colorPopup then self._colorPopup:Destroy() self._colorPopup=nil end
        main.Visible=self._visible shadow.Visible=self._visible notifications.Visible=self._visible
    end
    function window:ToggleVisibility() self:SetVisibility(not self._visible) end
    function window:Open() self:SetVisibility(true) end
    function window:Close() self:SetVisibility(false) end
    function window:Toggle() self:ToggleVisibility() end
    function window:SetToggleKey(value) self._toggleKey=typeof(value)=="EnumItem" and value or Enum.KeyCode[keyName(value)] or self._toggleKey end
    function window:SetTitle(value) brandName.Text=tostring(value or "Argon Utility") end
    function window:SetLogo(value) setBrandLogo(value) self._logo=value end
    function window:SetTheme(value) return Argon:SetTheme(value) end
    function window:GetThemes() return Argon:GetThemes() end
    function window:SetSize(value)
        local width,height
        if typeof(value)=="Vector2" then width,height=value.X,value.Y elseif type(value)=="table" then width,height=value[1] or value.X,value[2] or value.Y end
        local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
        local minWidth=math.min(self._minSize.X,math.max(360,viewport.X-20)) local minHeight=math.min(self._minSize.Y,math.max(340,viewport.Y-20))
        width=math.clamp(tonumber(width) or main.AbsoluteSize.X,minWidth,math.max(minWidth,math.min(1200,viewport.X-20))) height=math.clamp(tonumber(height) or main.AbsoluteSize.Y,minHeight,math.max(minHeight,math.min(820,viewport.Y-20)))
        self._userSized=true
        main.Size=UDim2.fromOffset(width,height) shadow.Size=UDim2.fromOffset(width+22,height+22)
    end

    local function makeOverlay(titleText,iconName,position,size)
        local card=create("Frame",{Active=true,AnchorPoint=Vector2.new(1,0),BackgroundColor3=C.Window,BackgroundTransparency=.06,BorderSizePixel=0,Position=position,Size=size,ZIndex=70,Parent=gui})
        corner(card,14) stroke(card,C.Border,.08,1) gradient(card,C.Surface,C.Window,120)
        local header=create("Frame",{Active=true,BackgroundTransparency=1,Size=UDim2.new(1,0,0,48),ZIndex=71,Parent=card})
        local iconBox=create("Frame",{BackgroundColor3=C.Accent,BackgroundTransparency=.82,BorderSizePixel=0,Position=UDim2.fromOffset(11,10),Size=UDim2.fromOffset(28,28),ZIndex=72,Parent=header}) corner(iconBox,9)
        drawIcon(iconBox,iconName,C.AccentLight,17)
        text(header,titleText,11,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(48,5),Size=UDim2.new(1,-92,0,24),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=72})
        local meta=text(header,"0",9,C.Dim,Enum.Font.GothamBold,{Position=UDim2.fromOffset(48,25),Size=UDim2.new(1,-92,0,16),ZIndex=72})
        local collapse=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Surface,BackgroundTransparency=.12,BorderSizePixel=0,Position=UDim2.new(1,-38,0,10),Size=UDim2.fromOffset(28,28),Text="-",TextColor3=C.Muted,TextSize=14,Font=Enum.Font.GothamBold,ZIndex=72,Parent=header}) corner(collapse,8)
        create("Frame",{BackgroundColor3=C.BorderSoft,BackgroundTransparency=.3,BorderSizePixel=0,Position=UDim2.fromOffset(10,47),Size=UDim2.new(1,-20,0,1),ZIndex=72,Parent=card})
        local body=create("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(8,56),ScrollBarImageColor3=C.Border,ScrollBarThickness=2,Size=UDim2.new(1,-16,1,-64),ZIndex=71,Parent=card})
        local layout=create("UIListLayout",{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder,Parent=body}) bindCanvas(body,layout,6)
        local expandedSize=size local collapsed=false
        connect(collapse.MouseButton1Click,function()
            collapsed=not collapsed body.Visible=not collapsed collapse.Text=collapsed and "+" or "-"
            tween(card,.22,{Size=collapsed and UDim2.fromOffset(size.X.Offset,48) or expandedSize},Enum.EasingStyle.Quart)
        end)
        local draggingOverlay=false local dragStartOverlay local startOverlayPosition
        connect(header.InputBegan,function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingOverlay=true dragStartOverlay=input.Position startOverlayPosition=card.Position end
        end)
        connect(UserInputService.InputChanged,function(input)
            if draggingOverlay and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
                local delta=input.Position-dragStartOverlay card.Position=UDim2.new(startOverlayPosition.X.Scale,startOverlayPosition.X.Offset+delta.X,startOverlayPosition.Y.Scale,startOverlayPosition.Y.Offset+delta.Y)
            end
        end)
        connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingOverlay=false end end)
        return {Root=card,Header=header,Body=body,Layout=layout,Meta=meta}
    end

    local playerOverlay=makeOverlay("PLAYER LIST","users",UDim2.new(1,-18,0,72),UDim2.fromOffset(270,262))
    local keybindOverlay=makeOverlay("ACTIVE BINDS","keyboard",UDim2.new(1,-18,0,348),UDim2.fromOffset(270,214))
    playerOverlay.Root.Visible=options.PlayerList~=false keybindOverlay.Root.Visible=options.KeybindList~=false
    window.PlayerListOverlay=playerOverlay.Root window.KeybindListOverlay=keybindOverlay.Root
    function window:SetPlayerListVisible(value) playerOverlay.Root.Visible=value~=false return self end
    function window:SetKeybindListVisible(value) keybindOverlay.Root.Visible=value~=false return self end
    function window:TogglePlayerList() return self:SetPlayerListVisible(not playerOverlay.Root.Visible) end
    function window:ToggleKeybindList() return self:SetKeybindListVisible(not keybindOverlay.Root.Visible) end

    local function clearOverlayRows(body)
        for _,child in ipairs(body:GetChildren()) do if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end end
    end
    local function refreshPlayers()
        clearOverlayRows(playerOverlay.Body)
        local playerList=Players:GetPlayers()
        table.sort(playerList,function(a,b) if a==LocalPlayer then return true elseif b==LocalPlayer then return false end return a.DisplayName:lower()<b.DisplayName:lower() end)
        playerOverlay.Meta.Text=tostring(#playerList).." CONNECTED"
        for _,player in ipairs(playerList) do
            local row=create("Frame",{BackgroundColor3=C.Surface,BackgroundTransparency=.16,BorderSizePixel=0,Size=UDim2.new(1,-4,0,42),ZIndex=72,Parent=playerOverlay.Body}) corner(row,9)
            local face=create("ImageLabel",{BackgroundColor3=C.Active,BorderSizePixel=0,Position=UDim2.fromOffset(6,6),Size=UDim2.fromOffset(30,30),Image="",ZIndex=73,Parent=row}) corner(face,8)
            task.spawn(function() local ok,image=pcall(Players.GetUserThumbnailAsync,Players,player.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size48x48) if ok and face.Parent then face.Image=image end end)
            text(row,player.DisplayName,10,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(44,3),Size=UDim2.new(1,-94,0,20),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=73})
            text(row,"@"..player.Name,9,C.Dim,Enum.Font.Gotham,{Position=UDim2.fromOffset(44,20),Size=UDim2.new(1,-94,0,17),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=73})
            if player==LocalPlayer then
                local you=text(row,"YOU",8,C.AccentLight,Enum.Font.GothamBold,{BackgroundColor3=C.Accent,BackgroundTransparency=.82,Position=UDim2.new(1,-45,.5,-10),Size=UDim2.fromOffset(36,20),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=73}) corner(you,10)
            end
        end
    end
    function window:_refreshKeybindOverlay()
        clearOverlayRows(keybindOverlay.Body)
        local shown=0
        for _,entry in ipairs(self._keybindEntries) do
            if entry.Element and entry.Element.Root and entry.Element.Root.Parent and entry.Visible~=false then
                shown+=1
                local row=create("Frame",{BackgroundColor3=entry.Active and C.Active or C.Surface,BackgroundTransparency=.14,BorderSizePixel=0,Size=UDim2.new(1,-4,0,36),ZIndex=72,Parent=keybindOverlay.Body}) corner(row,9)
                entry.OverlayRow=row
                local state=create("Frame",{BackgroundColor3=entry.Active and C.Success or C.Dim,BorderSizePixel=0,Position=UDim2.fromOffset(9,14),Size=UDim2.fromOffset(7,7),ZIndex=73,Parent=row}) corner(state,7)
                text(row,entry.Name,10,entry.Active and C.Text or C.Muted,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(25,0),Size=UDim2.new(1,-86,1,0),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=73})
                local key=text(row,entry.Key or "None",8,C.AccentLight,Enum.Font.GothamBold,{BackgroundColor3=C.Accent,BackgroundTransparency=.84,Position=UDim2.new(1,-58,.5,-11),Size=UDim2.fromOffset(49,22),TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=73}) corner(key,7)
                entry.OverlayState=state entry.OverlayKey=key
            end
        end
        keybindOverlay.Meta.Text=tostring(shown).." REGISTERED"
        if shown==0 then text(keybindOverlay.Body,"Keybind controls appear here",10,C.Dim,Enum.Font.GothamMedium,{Size=UDim2.new(1,-4,0,44),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=72}) end
    end
    connect(Players.PlayerAdded,refreshPlayers) connect(Players.PlayerRemoving,function() task.defer(refreshPlayers) end)
    refreshPlayers() window:_refreshKeybindOverlay()
    function window:Dialog(config)
        config=config or {}
        local overlay=create("Frame",{Active=true,BackgroundColor3=Color3.new(),BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=105,Parent=gui})
        local panel=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(380,0),ZIndex=106,Parent=overlay})
        corner(panel,15) stroke(panel,C.Border,.05,1)
        local dialogTitle=text(panel,tostring(config.Title or "Confirm action"),16,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(20,15),Size=UDim2.new(1,-58,0,24),ZIndex=107})
        local dialogBody=text(panel,tostring(config.Content or config.Description or ""),11,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(20,47),Size=UDim2.new(1,-40,0,50),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=107})
        local closeButton=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Position=UDim2.new(1,-37,0,13),Size=UDim2.fromOffset(24,24),Text="×",TextColor3=C.Dim,TextSize=19,Font=Enum.Font.Gotham,ZIndex=108,Parent=panel})
        local buttonHost=create("Frame",{BackgroundTransparency=1,Position=UDim2.new(0,20,1,-51),Size=UDim2.new(1,-40,0,34),ZIndex=107,Parent=panel})
        create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Right,Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder,Parent=buttonHost})
        local dialog={Root=overlay,Panel=panel,Title=dialogTitle,Body=dialogBody,Visible=false}
        function dialog:Close()
            if not self.Root.Parent or not self.Visible then return end
            self.Visible=false tween(overlay,.18,{BackgroundTransparency=1}) tween(panel,.18,{Size=UDim2.fromOffset(380,0)})
            task.delay(.2,function() if overlay.Parent then overlay.Visible=false end end)
        end
        function dialog:Show()
            if not self.Root.Parent then return end
            self.Visible=true overlay.Visible=true panel.Size=UDim2.fromOffset(380,0) overlay.BackgroundTransparency=1
            tween(overlay,.18,{BackgroundTransparency=.38}) tween(panel,.24,{Size=UDim2.fromOffset(380,160)},Enum.EasingStyle.Back)
        end
        function dialog:Destroy() if self.Root then self.Root:Destroy() end end
        connect(closeButton.MouseButton1Click,function() dialog:Close() end)
        local buttons=config.Buttons or {{Title="Okay",Variant="Primary"}}
        for _,buttonConfig in ipairs(buttons) do
            local primary=buttonConfig.Variant=="Primary" or buttonConfig.Primary==true
            local button=create("TextButton",{AutoButtonColor=false,BackgroundColor3=primary and C.Accent or C.Surface,BorderSizePixel=0,Size=UDim2.fromOffset(math.max(82,#tostring(buttonConfig.Title or buttonConfig.Name or "Button")*7+28),34),Text=tostring(buttonConfig.Title or buttonConfig.Name or "Button"),TextColor3=primary and Color3.new(1,1,1) or C.Muted,TextSize=10,Font=Enum.Font.GothamBold,ZIndex=108,Parent=buttonHost})
            corner(button,9) stroke(button,primary and C.Accent or C.BorderSoft,.18,1) hover(button,button.BackgroundColor3,primary and C.AccentLight or C.Hover)
            connect(button.MouseButton1Click,function() safeCall(buttonConfig.Callback,dialog) if buttonConfig.AutoClose~=false then dialog:Close() end end)
        end
        if config.Show~=false then dialog:Show() end
        return dialog
    end
    window.Popup=window.Dialog
    function window:_select(tab)
        if self.ActiveTab==tab then return end
        self._tabTransitionToken+=1
        local transitionToken=self._tabTransitionToken
        local oldTab=self.ActiveTab
        local oldIndex=oldTab and table.find(self.Tabs,oldTab) or 0
        local nextIndex=table.find(self.Tabs,tab) or oldIndex
        local direction=nextIndex>=oldIndex and 1 or -1
        if self._dropdownPopup then self._dropdownPopup:Destroy() self._dropdownPopup=nil end
        if self._colorPopup then self._colorPopup:Destroy() self._colorPopup=nil end
        if oldTab then
            oldTab.Accent.Visible=false
            tween(oldTab.Page,.17,{Position=UDim2.fromOffset(18-direction*16,14)},Enum.EasingStyle.Quart)
            tween(oldTab.TabButton,.15,{BackgroundTransparency=1,BackgroundColor3=C.Surface})
            tween(oldTab.IconBox,.15,{BackgroundColor3=C.Active,Rotation=0}) recolorIcon(oldTab.Icon,C.Muted)
            oldTab.ButtonTitle.TextColor3=C.Muted
        end
        self.ActiveTab=tab tab.Page.Position=UDim2.fromOffset(18+direction*18,14) tab.Page.Visible=true tab.Accent.Visible=true
        tween(tab.TabButton,.18,{BackgroundTransparency=.05,BackgroundColor3=C.Active})
        tween(tab.IconBox,.2,{BackgroundColor3=C.Accent,Rotation=direction*3},Enum.EasingStyle.Back) recolorIcon(tab.Icon,Color3.new(1,1,1))
        tween(tab.Page,.21,{Position=UDim2.fromOffset(18,14)},Enum.EasingStyle.Quart)
        tab.ButtonTitle.TextColor3=C.Text
        tween(pageTitle,.08,{TextTransparency=1}) tween(eyebrow,.08,{TextTransparency=1})
        task.delay(.08,function()
            if transitionToken~=self._tabTransitionToken then return end
            pageTitle.Text=tab.Name eyebrow.Text="ARGON / "..tab.Name:upper()
            tween(pageTitle,.16,{TextTransparency=0}) tween(eyebrow,.16,{TextTransparency=0})
        end)
        task.delay(.18,function()
            if transitionToken~=self._tabTransitionToken then return end
            if oldTab and oldTab~=tab then oldTab.Page.Visible=false oldTab.Page.Position=UDim2.fromOffset(18,14) end
            tween(tab.IconBox,.12,{Rotation=0})
        end)
        search.Text="" tab:_filter("")
        if self._refreshSectionMenu then self:_refreshSectionMenu() end
    end

    function window:CreateTab(name,iconName)
        local tab={Name=tostring(name or "Tab"),IconName=tostring(iconName or "activity"),Window=self,_elements={},_sections={},_controlCount=0}
        local button=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Surface,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,-4,0,43),Text="",Parent=tabList}) corner(button,10)
        tab.TabButton=button
        tab.Accent=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,Position=UDim2.fromOffset(0,10),Size=UDim2.fromOffset(2,23),Visible=false,Parent=button}) corner(tab.Accent,2)
        tab.IconBox=create("Frame",{BackgroundColor3=C.Active,BackgroundTransparency=.15,BorderSizePixel=0,Position=UDim2.fromOffset(9,7),Size=UDim2.fromOffset(29,29),Parent=button}) corner(tab.IconBox,9)
        tab.Icon=drawIcon(tab.IconBox,tab.IconName,C.Muted)
        tab.ButtonTitle=text(button,tab.Name,12,C.Muted,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(48,0),Size=UDim2.new(1,-78,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
        tab.Count=text(button,"0",9,C.Dim,Enum.Font.GothamBold,{Position=UDim2.new(1,-27,0,0),Size=UDim2.fromOffset(20,43),TextXAlignment=Enum.TextXAlignment.Center})
        local page=create("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(18,14),ScrollBarImageColor3=C.Border,ScrollBarThickness=3,Size=UDim2.new(1,-28,1,-20),Visible=false,Parent=pageHost})
        padding(page,6,12,4,16)
        local pageLayout=create("UIListLayout",{Padding=UDim.new(0,12),SortOrder=Enum.SortOrder.LayoutOrder,Parent=page}) bindCanvas(page,pageLayout,24)
        tab.Page=page

        function tab:_updateCount() self.Count.Text=tostring(self._controlCount) end
        function tab:_filter(query)
            query=tostring(query or ""):lower()
            for _,section in ipairs(self._sections) do
                local visible=0
                for _,element in ipairs(section.Elements) do
                    local match=query=="" or element.Name:lower():find(query,1,true) or section.Name:lower():find(query,1,true)
                    element.Root.Visible=match and true or false if match then visible+=1 end
                end
                section.Root.Visible=visible>0 or query==""
            end
        end

        function tab:CreateSection(sectionName)
            if type(sectionName)=="table" then sectionName=sectionName.Title or sectionName.Name end
            local section={Name=tostring(sectionName or "Section"),Elements={}}
            local root=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,Parent=page}) section.Root=root
            local header=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,31),Parent=root})
            local accent=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,Position=UDim2.fromOffset(1,11),Size=UDim2.fromOffset(3,10),Parent=header}) corner(accent,3)
            text(header,section.Name:upper(),10,C.Muted,Enum.Font.GothamBold,{Position=UDim2.fromOffset(13,0),Size=UDim2.new(1,-13,1,0)})
            local body=create("Frame",{BackgroundColor3=C.Background,BackgroundTransparency=.56,BorderSizePixel=0,Position=UDim2.fromOffset(0,31),Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Parent=root})
            corner(body,13) stroke(body,C.BorderSoft,.28,1) padding(body,8,8,8,8)
            section.Body=body section.Layout=create("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder,Parent=body})
            function section:_build(method,...)
                local previous=tab._currentSection tab._currentSection=self
                local result=table.pack(pcall(tab[method],tab,...)) tab._currentSection=previous
                if not result[1] then error(result[2],2) end
                return table.unpack(result,2,result.n)
            end
            for alias,method in pairs({Button="CreateButton",Toggle="CreateToggle",Slider="CreateSlider",Dropdown="CreateDropdown",Input="CreateInput",Keybind="CreateKeybind",Colorpicker="CreateColorPicker",ColorPicker="CreateColorPicker",Paragraph="CreateParagraph",Divider="CreateDivider",Space="CreateSpace"}) do
                local methodName=method
                section[alias]=function(self,...) return self:_build(methodName,...) end
                section[method]=section[alias]
            end
            self._currentSection=section table.insert(self._sections,section)
            if window.ActiveTab==self and window._refreshSectionMenu then window:_refreshSectionMenu() end
            return section
        end

        local function base(controlName,height,config)
            if not tab._currentSection then tab:CreateSection("General") end
            local root=create("Frame",{Name="Control",BackgroundColor3=C.Surface,BackgroundTransparency=.08,BorderSizePixel=0,ClipsDescendants=true,Size=UDim2.new(1,0,0,height or 54),Parent=tab._currentSection.Body}) corner(root,10)
            local element={Name=tostring(controlName or "Control"),Root=root,Section=tab._currentSection,_stroke=stroke(root,C.BorderSoft,.2,1)}
            function element:SetVisible(value) self.Root.Visible=value~=false return self end
            function element:SetTitle(value) self.Name=tostring(value or "Control") if self._title then self._title.Text=self.Name end return self end
            function element:SetDesc(value)
                local description=tostring(value or "")
                if not self._description then
                    self._description=text(root,"",10,C.Dim,Enum.Font.Gotham,{Position=UDim2.fromOffset(14,31),Size=UDim2.new(1,-28,0,18),TextTruncate=Enum.TextTruncate.AtEnd})
                    root.Size=UDim2.new(root.Size.X.Scale,root.Size.X.Offset,0,math.max(root.Size.Y.Offset,68))
                end
                self._description.Text=description self._description.Visible=description~="" return self
            end
            function element:Lock(reason)
                if self._lock then return self end
                local lock=create("TextButton",{Active=true,AutoButtonColor=false,BackgroundColor3=C.Window,BackgroundTransparency=.2,BorderSizePixel=0,Size=UDim2.fromScale(1,1),Text="",ZIndex=28,Parent=root}) corner(lock,10)
                local label=text(lock,"LOCKED"..(reason and reason~="" and " · "..tostring(reason) or ""),9,C.Warning,Enum.Font.GothamBold,{Position=UDim2.new(0,12,0,0),Size=UDim2.new(1,-24,1,0),TextXAlignment=Enum.TextXAlignment.Right,ZIndex=29})
                self._lock={Root=lock,Label=label} self.Locked=true return self
            end
            function element:Unlock() if self._lock then self._lock.Root:Destroy() self._lock=nil end self.Locked=false return self end
            function element:SetTooltip(value)
                self._tooltipText=tostring(value or "")
                if self._tooltipBound then return self end
                self._tooltipBound=true
                connect(root.MouseEnter,function()
                    if self._tooltipText=="" then return end
                    if window._tooltip then window._tooltip:Destroy() end
                    local mouse=UserInputService:GetMouseLocation()
                    local tip=create("TextLabel",{BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromOffset(mouse.X+12,mouse.Y+12),Size=UDim2.fromOffset(math.clamp(#self._tooltipText*6+24,110,300),32),Text=self._tooltipText,TextColor3=C.Muted,TextSize=10,Font=Enum.Font.GothamMedium,ZIndex=96,Parent=gui})
                    corner(tip,8) stroke(tip,C.Border,.08,1) window._tooltip=tip
                end)
                connect(root.MouseLeave,function() if window._tooltip then window._tooltip:Destroy() window._tooltip=nil end end)
                return self
            end
            element.Tooltip=element.SetTooltip
            function element:Destroy()
                if self._onDestroy then self:_onDestroy() end
                if self.Root then self.Root:Destroy() end
                for index,item in ipairs(self.Section.Elements) do if item==self then table.remove(self.Section.Elements,index) break end end
                for index,item in ipairs(tab._elements) do if item==self then table.remove(tab._elements,index) break end end
                tab._controlCount=math.max(0,tab._controlCount-1) tab:_updateCount()
            end
            table.insert(tab._currentSection.Elements,element) table.insert(tab._elements,element) tab._controlCount+=1 tab:_updateCount()
            local description=config and (config.Description or config.Desc)
            if description and tostring(description)~="" then element:SetDesc(description) end
            return root,element
        end
        local function title(root,value,width,y)
            return text(root,value,13,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,y or 0),Size=UDim2.new(1,width or -90,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
        end

        function tab:CreateLabel(value)
            local root,element=base(tostring(value or ""),44) root.BackgroundTransparency=.45 root.AutomaticSize=Enum.AutomaticSize.Y
            local badge=create("TextLabel",{BackgroundColor3=C.Accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.fromOffset(11,10),Size=UDim2.fromOffset(24,24),Text="i",TextColor3=C.AccentLight,TextSize=12,Font=Enum.Font.GothamBold,Parent=root}) corner(badge,8)
            local label=text(root,tostring(value or ""),11,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(44,7),Size=UDim2.new(1,-56,0,30),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true})
            element.Type="Label" element.CurrentValue=tostring(value or "")
            function element:Set(nextValue) self.CurrentValue=tostring(nextValue or "") self.Name=self.CurrentValue label.Text=self.CurrentValue end
            return element
        end

        function tab:CreateButton(config)
            config=config or {}
            local root,element=base(config.Name,50,config) element._title=title(root,config.Name or "Button",-70)
            local action=create("TextLabel",{BackgroundColor3=C.Accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.new(1,-44,0,9),Size=UDim2.fromOffset(32,32),Text="→",TextColor3=C.AccentLight,TextSize=15,Font=Enum.Font.GothamBold,Parent=root}) corner(action,9)
            local click=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Text="",Parent=root}) element.Type="Button"
            connect(click.MouseEnter,function() tween(root,.15,{BackgroundColor3=C.Hover}) tween(action,.15,{BackgroundTransparency=.15,TextColor3=Color3.new(1,1,1)}) end)
            connect(click.MouseLeave,function() tween(root,.18,{BackgroundColor3=C.Surface}) tween(action,.18,{BackgroundTransparency=.84,TextColor3=C.AccentLight}) end)
            connect(click.MouseButton1Click,function() tween(root,.08,{BackgroundColor3=C.Active}) task.delay(.09,function() if root.Parent then tween(root,.16,{BackgroundColor3=C.Hover}) end end) safeCall(config.Callback) end)
            return element
        end

        function tab:CreateToggle(config)
            config=config or {}
            local root,element=base(config.Name,54,config) element._title=title(root,config.Name or "Toggle",-82)
            local track=create("Frame",{BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.new(1,-58,.5,-12),Size=UDim2.fromOffset(44,24),Parent=root}) corner(track,12)
            local knob=create("Frame",{BackgroundColor3=C.Muted,BorderSizePixel=0,Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(18,18),Parent=track}) corner(knob,9)
            local click=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Text="",Parent=root})
            element.Type="Toggle" element.CurrentValue=config.CurrentValue==true
            local function render(animated)
                local duration=animated and .18 or 0
                if element.CurrentValue then tween(track,duration,{BackgroundColor3=C.Accent}) tween(knob,duration,{Position=UDim2.fromOffset(23,3),BackgroundColor3=Color3.new(1,1,1)})
                else tween(track,duration,{BackgroundColor3=C.Input}) tween(knob,duration,{Position=UDim2.fromOffset(3,3),BackgroundColor3=C.Muted}) end
            end
            function element:Set(value)
                local nextValue=value==true local didChange=self.CurrentValue~=nextValue self.CurrentValue=nextValue render(true)
                if didChange then changed(self) safeCall(config.Callback,self.CurrentValue) end
            end
            connect(click.MouseButton1Click,function() element:Set(not element.CurrentValue) end) hover(root,C.Surface,C.Hover)
            render(false) registerFlag(config.Flag,element) return element
        end

        function tab:CreateSlider(config)
            config=config or {}
            local range=config.Range or {0,100} local minimum=tonumber(range[1]) or 0 local maximum=tonumber(range[2]) or 100 local increment=tonumber(config.Increment) or 1
            local root,element=base(config.Name,72,config) element._title=title(root,config.Name or "Slider",-100,-13)
            local valueBox=create("TextBox",{BackgroundColor3=C.Input,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.GothamBold,Position=UDim2.new(1,-73,0,9),Size=UDim2.fromOffset(59,26),Text="0",TextColor3=C.AccentLight,TextSize=10,Parent=root}) corner(valueBox,8) stroke(valueBox,C.BorderSoft,.25,1)
            local bar=create("Frame",{Active=true,BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.fromOffset(14,51),Size=UDim2.new(1,-28,0,5),Parent=root}) corner(bar,4)
            local fill=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,Size=UDim2.new(0,0,1,0),Parent=bar}) corner(fill,4) gradient(fill,C.AccentLight,C.AccentDark,0)
            local handle=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromScale(0,.5),Size=UDim2.fromOffset(13,13),Parent=bar}) corner(handle,7) stroke(handle,C.Accent,0,2)
            element.Type="Slider" element.CurrentValue=tonumber(config.CurrentValue) or minimum
            local function round(value)
                value=math.clamp(value,minimum,maximum) value=math.floor((value-minimum)/increment+.5)*increment+minimum
                local decimals=tostring(increment):match("%.(%d+)") if decimals then local power=10^#decimals value=math.floor(value*power+.5)/power end
                return math.clamp(value,minimum,maximum)
            end
            local function render()
                local ratio=maximum==minimum and 0 or (element.CurrentValue-minimum)/(maximum-minimum)
                fill.Size=UDim2.new(ratio,0,1,0) handle.Position=UDim2.new(ratio,0,.5,0) valueBox.Text=tostring(element.CurrentValue)..(config.Suffix or "")
            end
            function element:Set(value)
                local parsed=tonumber(value) or tonumber(tostring(value):match("[-%d%.]+")) if not parsed then render() return end
                local nextValue=round(parsed) local didChange=self.CurrentValue~=nextValue self.CurrentValue=nextValue render()
                if didChange then changed(self) safeCall(config.Callback,self.CurrentValue) end
            end
            local draggingSlider=false
            local function fromX(x) local ratio=math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1) element:Set(minimum+(maximum-minimum)*ratio) end
            connect(bar.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=true fromX(input.Position.X) end end)
            connect(UserInputService.InputChanged,function(input) if draggingSlider and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then fromX(input.Position.X) end end)
            connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=false end end)
            connect(valueBox.FocusLost,function() element:Set(valueBox.Text) end) hover(root,C.Surface,C.Hover)
            element.CurrentValue=round(element.CurrentValue) render() registerFlag(config.Flag,element) return element
        end

        function tab:CreateInput(config)
            config=config or {}
            local root,element=base(config.Name,70,config)
            element._title=text(root,config.Name or "Input",11,C.Muted,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,4),Size=UDim2.new(1,-28,0,20)})
            local inputField=create("Frame",{BackgroundColor3=C.Input,BorderSizePixel=0,ClipsDescendants=true,Position=UDim2.fromOffset(13,28),Size=UDim2.new(1,-26,0,31),Parent=root})
            corner(inputField,9) local inputStroke=stroke(inputField,C.BorderSoft,.22,1)
            local input=create("TextBox",{BackgroundTransparency=1,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.Gotham,MultiLine=false,PlaceholderColor3=C.Dim,PlaceholderText=config.PlaceholderText or "Enter value...",Position=UDim2.fromOffset(11,0),Size=UDim2.new(1,-22,1,0),Text=tostring(config.CurrentValue or ""),TextColor3=C.Text,TextSize=11,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,Parent=inputField})
            element.Type="Input" element.CurrentValue=tostring(config.CurrentValue or "")
            function element:Set(value)
                local nextValue=tostring(value or "") local didChange=self.CurrentValue~=nextValue self.CurrentValue=nextValue input.Text=nextValue
                if didChange then changed(self) safeCall(config.Callback,nextValue) end
            end
            connect(input.Focused,function() tween(inputStroke,.15,{Color=C.Accent,Transparency=0}) end)
            connect(input.FocusLost,function()
                tween(inputStroke,.18,{Color=C.BorderSoft,Transparency=.22}) element:Set(input.Text)
                if config.RemoveTextAfterFocusLost then input.Text="" end
            end)
            registerFlag(config.Flag,element) return element
        end

        function tab:CreateKeybind(config)
            config=config or {}
            local root,element=base(config.Name,54,config) element._title=title(root,config.Name or "Keybind",-105)
            local bind=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.new(1,-91,.5,-14),Size=UDim2.fromOffset(77,28),Text="None",TextColor3=C.AccentLight,TextSize=10,Font=Enum.Font.GothamBold,Parent=root}) corner(bind,8) stroke(bind,C.BorderSoft,.24,1)
            element.Type="Keybind" element.CurrentKeybind=keyName(config.CurrentKeybind) element.CurrentValue=element.CurrentKeybind
            local overlayEntry={Element=element,Name=tostring(config.Name or "Keybind"),Key=element.CurrentKeybind,Active=config.Active==true,Visible=config.DisplayInKeybindList~=false}
            table.insert(window._keybindEntries,overlayEntry)
            local listening=false
            local function render() bind.Text=listening and "PRESS KEY" or element.CurrentKeybind bind.TextColor3=listening and C.Warning or C.AccentLight end
            function element:Set(value)
                local nextValue=keyName(value) local didChange=self.CurrentKeybind~=nextValue self.CurrentKeybind=nextValue self.CurrentValue=nextValue listening=false render()
                overlayEntry.Key=nextValue window:_refreshKeybindOverlay()
                if didChange then changed(self) safeCall(config.Callback,nextValue) end
            end
            function element:SetActive(value) overlayEntry.Active=value==true window:_refreshKeybindOverlay() return self end
            function element:SetOverlayVisible(value) overlayEntry.Visible=value~=false window:_refreshKeybindOverlay() return self end
            function element:_onDestroy()
                for index,entry in ipairs(window._keybindEntries) do if entry==overlayEntry then table.remove(window._keybindEntries,index) break end end
                window:_refreshKeybindOverlay()
            end
            connect(bind.MouseButton1Click,function() listening=not listening render() end)
            connect(UserInputService.InputBegan,function(input,processed)
                if processed or input.UserInputType~=Enum.UserInputType.Keyboard then return end
                if listening then
                    if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.Backspace then element:Set("None") else element:Set(input.KeyCode.Name) end
                elseif element.CurrentKeybind~="None" and input.KeyCode.Name==element.CurrentKeybind then
                    if config.Toggle==true then element:SetActive(not overlayEntry.Active)
                    else element:SetActive(true) task.delay(.18,function() if element.Root and element.Root.Parent then element:SetActive(false) end end) end
                    safeCall(config.OnPressed or config.Pressed,element.CurrentKeybind,overlayEntry.Active)
                end
            end)
            hover(root,C.Surface,C.Hover) render() window:_refreshKeybindOverlay() registerFlag(config.Flag,element) return element
        end

        function tab:CreateDropdown(config)
            config=config or {}
            local multiple=config.MultipleOptions==true
            local root,element=base(config.Name,58,config)
            element._title=text(root,config.Name or "Dropdown",11,C.Muted,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,5),Size=UDim2.new(.45,-18,0,20),TextTruncate=Enum.TextTruncate.AtEnd})
            local selectButton=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Input,BorderSizePixel=0,ClipsDescendants=true,Position=UDim2.new(.45,0,0,10),Size=UDim2.new(.55,-14,0,37),Text="",Parent=root}) corner(selectButton,9)
            local selectStroke=stroke(selectButton,C.BorderSoft,.22,1)
            local selectedText=text(selectButton,"Select...",10,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(11,0),Size=UDim2.new(1,-45,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
            local chevronHost=create("Frame",{BackgroundTransparency=1,Position=UDim2.new(1,-31,.5,-10),Size=UDim2.fromOffset(20,20),Parent=selectButton})
            local chevronIcon=drawIcon(chevronHost,"chevron-down",C.Dim,16)
            element.Type="Dropdown" element.Options=copy(config.Options or {}) element.CurrentOption={}
            local initial=config.CurrentOption
            if type(initial)=="table" then element.CurrentOption=copy(initial) elseif initial~=nil and tostring(initial)~="" then element.CurrentOption={initial} end
            if not multiple and #element.CurrentOption>1 then element.CurrentOption={element.CurrentOption[1]} end
            element.CurrentValue=element.CurrentOption
            local function render()
                if #element.CurrentOption==0 then selectedText.Text="Select..." selectedText.TextColor3=C.Dim
                elseif multiple and #element.CurrentOption>2 then selectedText.Text=tostring(element.CurrentOption[1]).."  +"..tostring(#element.CurrentOption-1) selectedText.TextColor3=C.Text
                else
                    local parts={} for _,value in ipairs(element.CurrentOption) do table.insert(parts,tostring(value)) end
                    selectedText.Text=table.concat(parts,", ") selectedText.TextColor3=C.Text
                end
            end
            function element:Set(value)
                local nextSelection={}
                if type(value)=="table" then
                    for _,entry in ipairs(value) do if contains(self.Options,entry) then table.insert(nextSelection,entry) if not multiple then break end end end
                elseif contains(self.Options,value) then nextSelection={value} end
                local before=HttpService:JSONEncode(self.CurrentOption) self.CurrentOption=nextSelection self.CurrentValue=nextSelection render()
                if before~=HttpService:JSONEncode(nextSelection) then changed(self) safeCall(config.Callback,copy(nextSelection)) end
            end
            function element:Refresh(newOptions,keepCurrent)
                self.Options=copy(newOptions or {}) local retained={}
                if keepCurrent~=false then for _,selected in ipairs(self.CurrentOption) do if contains(self.Options,selected) then table.insert(retained,selected) end end end
                self.CurrentOption=retained self.CurrentValue=retained render()
            end
            local function closePopup()
                if window._dropdownPopup then window._dropdownPopup:Destroy() window._dropdownPopup=nil end
                tween(selectStroke,.15,{Color=C.BorderSoft,Transparency=.22})
                tween(chevronIcon,.16,{Rotation=0})
            end
            local function openPopup()
                closePopup()
                local absolute=selectButton.AbsolutePosition local popupWidth=math.max(210,selectButton.AbsoluteSize.X)
                local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
                local x=math.clamp(absolute.X,8,viewport.X-popupWidth-8)
                local popup=create("Frame",{BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromOffset(x,absolute.Y+selectButton.AbsoluteSize.Y+6),Size=UDim2.fromOffset(popupWidth,0),ZIndex=80,Parent=gui})
                window._dropdownPopup=popup corner(popup,12) stroke(popup,C.Border,.02,1)
                local filterField=create("Frame",{BackgroundColor3=C.Input,BorderSizePixel=0,ClipsDescendants=true,Position=UDim2.fromOffset(9,9),Size=UDim2.new(1,-18,0,32),ZIndex=81,Parent=popup}) corner(filterField,8)
                local filterIconHost=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(8,7),Size=UDim2.fromOffset(18,18),ZIndex=82,Parent=filterField}) drawIcon(filterIconHost,"search",C.Dim,15)
                local filter=create("TextBox",{BackgroundTransparency=1,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.Gotham,PlaceholderColor3=C.Dim,PlaceholderText="Filter options...",Position=UDim2.fromOffset(32,0),Size=UDim2.new(1,-42,1,0),Text="",TextColor3=C.Text,TextSize=10,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=82,Parent=filterField})
                local list=create("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(8,49),ScrollBarImageColor3=C.Border,ScrollBarThickness=2,Size=UDim2.new(1,-16,1,-57),ZIndex=81,Parent=popup})
                local layout=create("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder,Parent=list}) bindCanvas(list,layout,5)
                local records={}
                for _,option in ipairs(element.Options) do
                    local optionText=tostring(option) local selected=contains(element.CurrentOption,option)
                    local choice=create("TextButton",{AutoButtonColor=false,BackgroundColor3=selected and C.Active or C.Surface,BackgroundTransparency=.08,BorderSizePixel=0,Size=UDim2.new(1,-4,0,32),Text=optionText,TextColor3=selected and C.AccentLight or C.Muted,TextSize=10,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=82,Parent=list})
                    padding(choice,11,11,0,0) corner(choice,8) hover(choice,choice.BackgroundColor3,C.Hover) table.insert(records,{Button=choice,Text=optionText:lower()})
                    connect(choice.MouseButton1Click,function()
                        if multiple then
                            local nextSelection=copy(element.CurrentOption)
                            if contains(nextSelection,option) then for index,value in ipairs(nextSelection) do if value==option then table.remove(nextSelection,index) break end end else table.insert(nextSelection,option) end
                            element:Set(nextSelection) local active=contains(element.CurrentOption,option) choice.BackgroundColor3=active and C.Active or C.Surface choice.TextColor3=active and C.AccentLight or C.Muted
                        else element:Set({option}) closePopup() end
                    end)
                end
                connect(filter:GetPropertyChangedSignal("Text"),function()
                    local query=filter.Text:lower() for _,record in ipairs(records) do record.Button.Visible=query=="" or record.Text:find(query,1,true)~=nil end
                end)
                tween(selectStroke,.15,{Color=C.Accent,Transparency=0}) tween(chevronIcon,.16,{Rotation=180}) tween(popup,.2,{Size=UDim2.fromOffset(popupWidth,226)},Enum.EasingStyle.Back)
            end
            connect(selectButton.MouseButton1Click,function() if window._dropdownPopup then closePopup() else openPopup() end end)
            render() registerFlag(config.Flag,element) return element
        end

        function tab:CreateParagraph(config)
            if type(config)~="table" then config={Title="Information",Content=tostring(config or "")} end
            local root,element=base(config.Title or config.Name,68)
            local badge=create("TextLabel",{BackgroundColor3=C.Accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.fromOffset(12,13),Size=UDim2.fromOffset(30,30),Text=tostring(config.Icon or "i"),TextColor3=C.AccentLight,TextSize=13,Font=Enum.Font.GothamBold,Parent=root}) corner(badge,9)
            element._title=text(root,tostring(config.Title or config.Name or "Information"),12,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(53,8),Size=UDim2.new(1,-65,0,21),TextTruncate=Enum.TextTruncate.AtEnd})
            local contentLabel=text(root,tostring(config.Content or config.Description or ""),10,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(53,29),Size=UDim2.new(1,-65,0,30),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
            element.Type="Paragraph" element.CurrentValue=contentLabel.Text
            function element:Set(value) self.CurrentValue=tostring(value or "") contentLabel.Text=self.CurrentValue end
            function element:SetContent(value) self:Set(value) return self end
            return element
        end

        function tab:CreateDivider(config)
            local labelValue=type(config)=="table" and (config.Title or config.Name) or config
            local root,element=base(labelValue or "Divider",labelValue and 29 or 15)
            root.BackgroundTransparency=1 element._stroke.Transparency=1
            create("Frame",{AnchorPoint=Vector2.new(0,.5),BackgroundColor3=C.BorderSoft,BackgroundTransparency=.18,BorderSizePixel=0,Position=UDim2.new(0,4,.5,0),Size=labelValue and UDim2.new(.34,-8,0,1) or UDim2.new(1,-8,0,1),Parent=root})
            if labelValue then
                element._title=text(root,tostring(labelValue):upper(),9,C.Dim,Enum.Font.GothamBold,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(.3,0,1,0),TextXAlignment=Enum.TextXAlignment.Center})
                create("Frame",{AnchorPoint=Vector2.new(1,.5),BackgroundColor3=C.BorderSoft,BackgroundTransparency=.18,BorderSizePixel=0,Position=UDim2.new(1,-4,.5,0),Size=UDim2.new(.34,-8,0,1),Parent=root})
            end
            element.Type="Divider" return element
        end

        function tab:CreateSpace(size)
            local root,element=base("Space",math.clamp(tonumber(size) or 10,4,80))
            root.BackgroundTransparency=1 element._stroke.Transparency=1 element.Type="Space" return element
        end

        function tab:CreateColorPicker(config)
            config=config or {}
            local root,element=base(config.Name,58,config)
            element._title=text(root,config.Name or "Color picker",12,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,0),Size=UDim2.new(1,-108,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
            local swatch=create("TextButton",{AutoButtonColor=false,BackgroundColor3=typeof(config.Color)=="Color3" and config.Color or typeof(config.CurrentValue)=="Color3" and config.CurrentValue or C.Accent,BorderSizePixel=0,Position=UDim2.new(1,-94,.5,-15),Size=UDim2.fromOffset(80,30),Text="",Parent=root})
            corner(swatch,9) local swatchStroke=stroke(swatch,C.Border,.08,1)
            local hexLabel=text(swatch,"#000000",9,Color3.new(1,1,1),Enum.Font.GothamBold,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
            element.Type="ColorPicker" element.CurrentValue=swatch.BackgroundColor3
            local function hex(color) return string.format("#%02X%02X%02X",math.floor(color.R*255+.5),math.floor(color.G*255+.5),math.floor(color.B*255+.5)) end
            local function parseHex(value)
                local clean=tostring(value or ""):gsub("#","")
                if #clean~=6 then return nil end
                local number=tonumber(clean,16) if not number then return nil end
                return Color3.fromRGB(math.floor(number/65536)%256,math.floor(number/256)%256,number%256)
            end
            local function render() swatch.BackgroundColor3=element.CurrentValue hexLabel.Text=hex(element.CurrentValue) end
            function element:Set(value)
                local color=typeof(value)=="Color3" and value or parseHex(value) if not color then return end
                local didChange=self.CurrentValue~=color self.CurrentValue=color render()
                if didChange then changed(self) safeCall(config.Callback,color) end
            end
            local function closePicker()
                if window._colorPopup then window._colorPopup:Destroy() window._colorPopup=nil end
                tween(swatchStroke,.15,{Color=C.Border,Transparency=.08})
            end
            local function openPicker()
                closePicker() if window._dropdownPopup then window._dropdownPopup:Destroy() window._dropdownPopup=nil end
                local h,s,v=element.CurrentValue:ToHSV() local absolute=swatch.AbsolutePosition
                local popup=create("Frame",{BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromOffset(absolute.X-170,absolute.Y+38),Size=UDim2.fromOffset(250,0),ZIndex=84,Parent=gui})
                window._colorPopup=popup corner(popup,12) stroke(popup,C.Border,.02,1) padding(popup,10,10,10,10)
                local square=create("Frame",{Active=true,BackgroundColor3=Color3.fromHSV(h,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(10,10),Size=UDim2.new(1,-20,0,116),ZIndex=85,Parent=popup}) corner(square,8)
                local white=create("Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=86,Parent=square}) corner(white,8) gradient(white,Color3.new(1,1,1),Color3.new(1,1,1),0).Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})
                local black=create("Frame",{BackgroundColor3=Color3.new(),BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=87,Parent=square}) corner(black,8) gradient(black,Color3.new(),Color3.new(),90).Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)})
                local cursor=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromScale(s,1-v),Size=UDim2.fromOffset(11,11),ZIndex=88,Parent=square}) corner(cursor,6) stroke(cursor,Color3.new(),.2,2)
                local hue=create("Frame",{Active=true,BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(10,136),Size=UDim2.new(1,-20,0,13),ZIndex=85,Parent=popup}) corner(hue,7)
                create("UIGradient",{Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHSV(0,1,1)),ColorSequenceKeypoint.new(.17,Color3.fromHSV(.17,1,1)),ColorSequenceKeypoint.new(.33,Color3.fromHSV(.33,1,1)),ColorSequenceKeypoint.new(.5,Color3.fromHSV(.5,1,1)),ColorSequenceKeypoint.new(.67,Color3.fromHSV(.67,1,1)),ColorSequenceKeypoint.new(.83,Color3.fromHSV(.83,1,1)),ColorSequenceKeypoint.new(1,Color3.fromHSV(1,1,1))}),Parent=hue})
                local hueCursor=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromScale(h,.5),Size=UDim2.fromOffset(7,19),ZIndex=87,Parent=hue}) corner(hueCursor,4) stroke(hueCursor,Color3.new(),.2,1)
                local hexBox=create("TextBox",{BackgroundColor3=C.Input,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.GothamBold,Position=UDim2.fromOffset(10,159),Size=UDim2.new(1,-20,0,31),Text=hex(element.CurrentValue),TextColor3=C.Text,TextSize=10,ZIndex=86,Parent=popup}) corner(hexBox,8) stroke(hexBox,C.BorderSoft,.2,1)
                local draggingSquare=false local draggingHue=false
                local function updateSquare(x,y) s=math.clamp((x-square.AbsolutePosition.X)/math.max(1,square.AbsoluteSize.X),0,1) v=1-math.clamp((y-square.AbsolutePosition.Y)/math.max(1,square.AbsoluteSize.Y),0,1) cursor.Position=UDim2.fromScale(s,1-v) element:Set(Color3.fromHSV(h,s,v)) hexBox.Text=hex(element.CurrentValue) end
                local function updateHue(x) h=math.clamp((x-hue.AbsolutePosition.X)/math.max(1,hue.AbsoluteSize.X),0,1) hueCursor.Position=UDim2.fromScale(h,.5) square.BackgroundColor3=Color3.fromHSV(h,1,1) element:Set(Color3.fromHSV(h,s,v)) hexBox.Text=hex(element.CurrentValue) end
                connect(square.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSquare=true updateSquare(input.Position.X,input.Position.Y) end end)
                connect(hue.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingHue=true updateHue(input.Position.X) end end)
                connect(UserInputService.InputChanged,function(input) if draggingSquare then updateSquare(input.Position.X,input.Position.Y) elseif draggingHue then updateHue(input.Position.X) end end)
                connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSquare=false draggingHue=false end end)
                connect(hexBox.FocusLost,function() element:Set(hexBox.Text) hexBox.Text=hex(element.CurrentValue) end)
                tween(swatchStroke,.15,{Color=C.Accent,Transparency=0}) tween(popup,.2,{Size=UDim2.fromOffset(250,201)},Enum.EasingStyle.Back)
            end
            connect(swatch.MouseButton1Click,function() if window._colorPopup then closePicker() else openPicker() end end)
            render() registerFlag(config.Flag,element) return element
        end
        tab.Colorpicker=tab.CreateColorPicker
        tab.ColorPicker=tab.CreateColorPicker
        tab.Button=tab.CreateButton
        tab.Toggle=tab.CreateToggle
        tab.Slider=tab.CreateSlider
        tab.Dropdown=tab.CreateDropdown
        tab.Input=tab.CreateInput
        tab.Keybind=tab.CreateKeybind
        tab.Paragraph=tab.CreateParagraph
        tab.Divider=tab.CreateDivider
        tab.Space=tab.CreateSpace
        tab.Section=tab.CreateSection

        local compactNow=sidebar.AbsoluteSize.X<100
        tab.ButtonTitle.Visible=not compactNow tab.Count.Visible=not compactNow
        connect(button.MouseButton1Click,function() window:_select(tab) end) hover(button,C.Surface,C.Hover)
        table.insert(self.Tabs,tab) if not self.ActiveTab then self:_select(tab) end
        return tab
    end

    local sectionPopover=create("Frame",{BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.new(1,-222,0,52),Size=UDim2.fromOffset(210,0),AutomaticSize=Enum.AutomaticSize.Y,Visible=false,ZIndex=80,Parent=content}) corner(sectionPopover,12) stroke(sectionPopover,C.Border,.08,1) padding(sectionPopover,7,7,7,7)
    local sectionLayout=create("UIListLayout",{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder,Parent=sectionPopover})
    function window:_refreshSectionMenu()
        for _,child in ipairs(sectionPopover:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
        local active=self.ActiveTab
        if not active then sectionPopover.Visible=false return end
        for index,section in ipairs(active._sections) do
            local jump=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Surface,BackgroundTransparency=.12,BorderSizePixel=0,Size=UDim2.new(1,0,0,31),Text=string.format("%02d  %s",index,section.Name),TextColor3=C.Muted,TextSize=10,Font=Enum.Font.GothamMedium,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=81,Parent=sectionPopover})
            corner(jump,8) padding(jump,10,8,0,0) hover(jump,C.Surface,C.Hover)
            connect(jump.MouseButton1Click,function()
                sectionPopover.Visible=false
                local offset=section.Root.AbsolutePosition.Y-active.Page.AbsolutePosition.Y+active.Page.CanvasPosition.Y
                active.Page.CanvasPosition=Vector2.new(0,math.max(0,offset-8))
            end)
        end
    end
    connect(sectionsButton.MouseButton1Click,function() window:_refreshSectionMenu() sectionPopover.Visible=not sectionPopover.Visible end)

    local resizeGrip=create("TextButton",{Active=true,AutoButtonColor=false,AnchorPoint=Vector2.new(1,1),BackgroundTransparency=1,Position=UDim2.fromScale(1,1),Size=UDim2.fromOffset(30,30),Text="",ZIndex=95,Parent=main})
    for offset=0,2 do create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Dim,BackgroundTransparency=.15+offset*.16,BorderSizePixel=0,Position=UDim2.new(1,-7-offset*5,1,-7),Rotation=-45,Size=UDim2.fromOffset(2,10+offset*5),ZIndex=96,Parent=resizeGrip}) end

    local dragging=false local dragStart local startPosition local resizing=false local resizeStart local startSize
    connect(topbar.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true dragStart=input.Position startPosition=main.Position end
    end)
    connect(resizeGrip.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then resizing=true dragging=false resizeStart=input.Position startSize=main.AbsoluteSize end
    end)
    connect(UserInputService.InputChanged,function(input)
        if resizing and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local delta=input.Position-resizeStart window:SetSize(Vector2.new(startSize.X+delta.X,startSize.Y+delta.Y))
        elseif dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local delta=input.Position-dragStart main.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,startPosition.Y.Scale,startPosition.Y.Offset+delta.Y) shadow.Position=main.Position
        end
    end)
    connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false resizing=false end end)
    connect(hide.MouseButton1Click,function() window:SetVisibility(false) end)
    connect(search:GetPropertyChangedSignal("Text"),function() if window.ActiveTab then window.ActiveTab:_filter(search.Text) end end)
    connect(UserInputService.InputBegan,function(input,processed)
        if processed then return end
        if input.KeyCode==window._toggleKey then window:ToggleVisibility()
        elseif input.KeyCode==Enum.KeyCode.Slash and window._visible then search:CaptureFocus() end
    end)

    local function responsive()
        local camera=workspace.CurrentCamera if not camera then return end
        local viewport=camera.ViewportSize
        if not window._userSized then
            local width=math.clamp(viewport.X-28,math.min(560,viewport.X-20),980) local height=math.clamp(viewport.Y-42,math.min(400,viewport.Y-20),660)
            main.Size=UDim2.fromOffset(width,height) shadow.Size=UDim2.fromOffset(width+22,height+22)
        elseif main.AbsoluteSize.X>viewport.X-20 or main.AbsoluteSize.Y>viewport.Y-20 then
            local previous=window._userSized window:SetSize(main.AbsoluteSize) window._userSized=previous
        end
        local width=main.AbsoluteSize.X
        local compact=width<760 local sideWidth=compact and 72 or 232
        sidebar.Size=UDim2.new(0,sideWidth,1,0) content.Position=UDim2.fromOffset(sideWidth,0) content.Size=UDim2.new(1,-sideWidth,1,0)
        brandName.Visible=not compact brandSub.Visible=not compact brand.Position=UDim2.fromOffset(compact and 17 or 18,17)
        searchFrame.Visible=not compact navCaption.Visible=not compact profileName.Visible=not compact profileState.Visible=not compact
        profile.Size=compact and UDim2.fromOffset(42,36) or UDim2.new(1,-28,0,36) profile.Position=compact and UDim2.new(0,15,1,-48) or UDim2.new(0,14,1,-48)
        avatar.Position=compact and UDim2.fromOffset(8,5) or UDim2.fromOffset(5,5)
        tabList.Position=UDim2.fromOffset(compact and 11 or 12,compact and 72 or 146) tabList.Size=UDim2.new(1,compact and -18 or -24,1,compact and -132 or -205)
        for _,tab in ipairs(window.Tabs) do tab.ButtonTitle.Visible=not compact tab.Count.Visible=not compact end
        status.Visible=width>=620 sectionsButton.Visible=width>=720
        if not sectionsButton.Visible then sectionPopover.Visible=false end
    end
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"),responsive)
    if workspace.CurrentCamera then connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),responsive) end
    responsive()

    local splash=create("CanvasGroup",{BackgroundColor3=C.Window,BorderSizePixel=0,GroupTransparency=0,Size=UDim2.fromScale(1,1),ZIndex=120,Parent=main})
    gradient(splash,Color3.fromRGB(18,20,32),Color3.fromRGB(7,9,15),125)
    local splashGlowA=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.new(.5,160,.5,-120),Size=UDim2.fromOffset(360,360),ZIndex=121,Parent=splash}) corner(splashGlowA,180)
    local splashGlowB=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.AccentDark,BackgroundTransparency=.9,BorderSizePixel=0,Position=UDim2.new(.5,-190,.5,130),Size=UDim2.fromOffset(300,300),ZIndex=121,Parent=splash}) corner(splashGlowB,150)
    local loaderStage=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Surface,BackgroundTransparency=.22,BorderSizePixel=0,Position=UDim2.fromScale(.5,.48),Size=UDim2.fromOffset(380,286),ZIndex=122,Parent=splash}) corner(loaderStage,22) stroke(loaderStage,C.Border,.08,1)
    local loaderScale=create("UIScale",{Scale=.94,Parent=loaderStage}) tween(loaderScale,.42,{Scale=1},Enum.EasingStyle.Back)
    local orbit=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Position=UDim2.fromScale(.5,.33),Size=UDim2.fromOffset(112,112),Rotation=0,ZIndex=123,Parent=loaderStage})
    local orbitStroke=stroke(orbit,C.Accent,.42,1) corner(orbit,56)
    local orbitDot=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.AccentLight,BorderSizePixel=0,Position=UDim2.new(.5,0,0,0),Size=UDim2.fromOffset(9,9),ZIndex=124,Parent=orbit}) corner(orbitDot,9)
    local orbitDotTwo=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Success,BorderSizePixel=0,Position=UDim2.new(.5,0,1,0),Size=UDim2.fromOffset(6,6),ZIndex=124,Parent=orbit}) corner(orbitDotTwo,6)
    local splashMark=mountLogo(loaderStage,62,options.Logo,125) splashMark.AnchorPoint=Vector2.new(.5,.5) splashMark.Position=UDim2.fromScale(.5,.33)
    local splashMarkScale=create("UIScale",{Scale=.88,Parent=splashMark})
    local logoPulse=TweenService:Create(splashMarkScale,TweenInfo.new(.7,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Scale=1.04}) logoPulse:Play()
    local orbitSpin=TweenService:Create(orbit,TweenInfo.new(1.8,Enum.EasingStyle.Linear,Enum.EasingDirection.InOut,-1),{Rotation=360}) orbitSpin:Play()
    local glowPulse=TweenService:Create(splashGlowA,TweenInfo.new(1.2,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{BackgroundTransparency=.9,Size=UDim2.fromOffset(420,420)}) glowPulse:Play()
    text(loaderStage,options.LoadingTitle or options.Name or "Argon Utility",18,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(24,132),Size=UDim2.new(1,-48,0,28),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=124})
    local loadingStatus=text(loaderStage,"INITIALIZING",9,C.AccentLight,Enum.Font.GothamBold,{Position=UDim2.fromOffset(24,162),Size=UDim2.new(1,-48,0,20),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=124})
    local loadingDetail=text(loaderStage,options.LoadingSubtitle or "Preparing interface systems",10,C.Dim,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(24,183),Size=UDim2.new(1,-48,0,18),TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=124})
    local progressRail=create("Frame",{BackgroundColor3=C.Input,BorderSizePixel=0,ClipsDescendants=true,Position=UDim2.fromOffset(34,219),Size=UDim2.new(1,-68,0,7),ZIndex=124,Parent=loaderStage}) corner(progressRail,7)
    local progressFill=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,Size=UDim2.fromScale(0,1),ZIndex=125,Parent=progressRail}) corner(progressFill,7) gradient(progressFill,C.AccentLight,C.AccentDark,0)
    local percent=text(loaderStage,"0%",9,C.Muted,Enum.Font.GothamBold,{Position=UDim2.fromOffset(34,235),Size=UDim2.new(1,-68,0,18),TextXAlignment=Enum.TextXAlignment.Right,ZIndex=124})
    local stages={{.08,.22,"INITIALIZING","Mounting interface shell"},{.38,.52,"BUILDING CONTROLS","Registering tabs and overlays"},{.72,.8,"SYNCING CONFIG","Applying saved preferences"},{1.12,1,"READY","Interface ready"}}
    for _,stage in ipairs(stages) do
        task.delay(stage[1],function()
            if not splash.Parent then return end
            loadingStatus.Text=stage[3] loadingDetail.Text=stage[4] percent.Text=tostring(math.floor(stage[2]*100)).."%"
            tween(progressFill,.34,{Size=UDim2.fromScale(stage[2],1)},Enum.EasingStyle.Quart)
            loadingStatus.TextTransparency=.45 tween(loadingStatus,.2,{TextTransparency=0})
        end)
    end
    task.delay(1.42,function()
        if not splash.Parent then return end
        orbitSpin:Cancel() logoPulse:Cancel() glowPulse:Cancel()
        tween(loaderScale,.28,{Scale=1.05},Enum.EasingStyle.Quart) tween(splash,.32,{GroupTransparency=1})
        sidebar.Position=UDim2.fromOffset(-14,0) content.Position=UDim2.fromOffset(content.Position.X.Offset+14,0)
        tween(sidebar,.36,{Position=UDim2.fromOffset(0,0)},Enum.EasingStyle.Quart)
        tween(content,.36,{Position=UDim2.fromOffset(content.Position.X.Offset-14,0)},Enum.EasingStyle.Quart)
        task.delay(.34,function() if splash then splash:Destroy() end end)
    end)
    return window
end

return Argon
