-- EXU HUB v4 | Single cycle | Luau client
-- Best-effort client logic. Does not bypass server anti-cheat or teleport protection.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local guiParent = player:WaitForChild("PlayerGui")

local previous = guiParent:FindFirstChild("ExuHubV4")
if previous then previous:Destroy() end

local CONFIG = {
    speed = 48,
    approachMargin = 1.5,
    maximumRange = 5000,
    pathRetries = 4,
    waypointTimeout = 5,
    idleTimeout = 1.6,
    collectionTimeout = 5,
    deliveryTimeout = 15,
    maxCycleSeconds = 260,
}

local SIZE = { ["Pequeno"]=1, ["Médio"]=2, ["Medio"]=2, ["Grande"]=3, ["Enorme"]=4, ["Colossal"]=5 }
-- These are only fallback size priorities, NOT official rarity tiers.
local RARITIES = { ["Comum"]=1, ["Incomum"]=2, ["Raro"]=3, ["Épico"]=4, ["Epico"]=4,
    ["Lendário"]=5, ["Lendario"]=5, ["Mítico"]=6, ["Mitico"]=6,
    ["Ancestral"]=7, ["Divino"]=8, ["Secreto"]=9 }

local state = { busy=false, stop=false, alive=true, selected=nil, labels={} }
local function parts()
    local character = player.Character
    return character, character and character:FindFirstChildOfClass("Humanoid"),
        character and character:FindFirstChild("HumanoidRootPart")
end
local function loadValue(v)
    return type(v)=="string" and v ~= ""
end
local function carrying()
    return loadValue(player:GetAttribute("Carrying"))
end
local function inventory()
    return player:GetAttribute("Inv")
end
local function ownPen()
    local map = Workspace:FindFirstChild("Map")
    local pens = map and map:FindFirstChild("Pens")
    if not pens then return nil end
    local penName = player:GetAttribute("PenName")
    local pen = type(penName)=="string" and pens:FindFirstChild(penName)
    if pen and pen:GetAttribute("Owner")==player.UserId then return pen end
    for _, candidate in ipairs(pens:GetChildren()) do
        if candidate:GetAttribute("Owner")==player.UserId then return candidate end
    end
end
local function baseDestination()
    local pen = ownPen()
    if not pen then return nil end
    local spawn = pen:FindFirstChild("Spawn",true)
    if spawn and spawn:IsA("BasePart") then return spawn.Position + Vector3.new(0,3,0) end
    local floor = pen:FindFirstChild("Floor",true)
    if floor and floor:IsA("BasePart") then return floor.Position + Vector3.new(0,3,0) end
    return pen:GetPivot().Position
end
local function rank(model,prompt)
    for _, obj in ipairs({model,prompt}) do
        for _, key in ipairs({"Rarity","Raridade","Tier"}) do
            local v = obj:GetAttribute(key)
            if type(v)=="string" and RARITIES[v] then return RARITIES[v],true,v end
        end
    end
    local label = prompt.ObjectText or ""
    for size, number in pairs(SIZE) do
        if string.find(label,size,1,true) then return number,false,size end
    end
    return 0,false,"desconhecido"
end
local function scan()
    local runtime = Workspace:FindFirstChild("Runtime")
    local _,_,root = parts()
    if not runtime or not root then return {} end
    local result = {}
    for _, model in ipairs(runtime:GetChildren()) do
        if model:IsA("Model") then
            local rootPart = model:FindFirstChild("Root")
            local prompt = rootPart and rootPart:FindFirstChildOfClass("ProximityPrompt")
            if rootPart and rootPart:IsA("BasePart") and prompt and prompt.Enabled and prompt.ActionText=="Roubar" then
                local distance = (root.Position-rootPart.Position).Magnitude
                if distance<=CONFIG.maximumRange then
                    local score,official,detail = rank(model,prompt)
                    table.insert(result,{model=model,part=rootPart,prompt=prompt,score=score,
                        official=official,detail=detail,distance=distance,name=prompt.ObjectText})
                end
            end
        end
    end
    table.sort(result,function(a,b)
        if a.official ~= b.official then return a.official end
        if a.score ~= b.score then return a.score>b.score end
        return a.distance<b.distance
    end)
    return result
end

-- GUI
local gui = Instance.new("ScreenGui")
gui.Name="ExuHubV4"; gui.ResetOnSpawn=false; gui.Parent=guiParent
local frame=Instance.new("Frame")
frame.Name="Panel"; frame.Size=UDim2.fromOffset(350,348)
frame.Position=UDim2.new(.5,-175,.25,0); frame.BackgroundColor3=Color3.fromRGB(25,25,36)
frame.BorderSizePixel=0; frame.Active=true; frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local layout=Instance.new("UIListLayout")
layout.Padding=UDim.new(0,7); layout.HorizontalAlignment=Enum.HorizontalAlignment.Center; layout.Parent=frame
local pad=Instance.new("UIPadding")
pad.PaddingTop=UDim.new(0,8); pad.Parent=frame
local function label(s,h)
    local t=Instance.new("TextLabel")
    t.Size=UDim2.new(1,-20,0,h or 30); t.BackgroundTransparency=1
    t.TextColor3=Color3.fromRGB(238,238,247); t.Text=s; t.TextWrapped=true
    t.Font=Enum.Font.GothamBold; t.TextSize=14; t.Parent=frame
    return t
end
local function button(s,fn)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,-24,0,40); b.BackgroundColor3=Color3.fromRGB(71,51,112)
    b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamBold
    b.TextSize=14; b.Text=s; b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    b.MouseButton1Click:Connect(fn)
    return b
end
label("EXU HUB v4  |  UM CICLO POR CLIQUE",35)
local statusLabel=label("Estado: pronto",30)
local targetLabel=label("Alvo: não selecionado",43)
local baseLabel=label("Base: aguardando",24)
local function status(s)
    if state.alive then statusLabel.Text="Estado: "..s end
    print("[EXU HUB v4] "..s)
end
local function updateBase()
    local pen=ownPen()
    if state.alive then baseLabel.Text="Base: "..(pen and pen.Name or "não encontrada") end
end
updateBase()

-- Move by accessible waypoints with retries. No local CFrame warp.
local function travel(destination,arrival,deadline)
    for attempt=1,CONFIG.pathRetries do
        if state.stop or not state.alive then return false,"cancelado" end
        local _,hum,root=parts()
        if not hum or not root then return false,"personagem indisponível" end
        if (root.Position-destination).Magnitude<=arrival then return true end
        if os.clock()>deadline then return false,"tempo geral esgotado" end
        hum.WalkSpeed=CONFIG.speed
        local path=PathfindingService:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4})
        local ok=pcall(function() path:ComputeAsync(root.Position,destination) end)
        if not ok or path.Status~=Enum.PathStatus.Success then
            return false,"sem caminho no mapa"
        end
        local blocked=false
        local blockConn=path.Blocked:Connect(function() blocked=true end)
        local repath=false
        for _,wp in ipairs(path:GetWaypoints()) do
            if state.stop or not state.alive then blockConn:Disconnect(); return false,"cancelado" end
            _,hum,root=parts()
            if not hum or not root then blockConn:Disconnect(); return false,"personagem indisponível" end
            if (root.Position-destination).Magnitude<=arrival then blockConn:Disconnect(); return true end
            if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end
            hum:MoveTo(wp.Position)
            local started=os.clock(); local still=0; local last=root.Position
            local reached=false
            while os.clock()-started<CONFIG.waypointTimeout do
                if state.stop or not state.alive then blockConn:Disconnect(); return false,"cancelado" end
                if os.clock()>deadline then blockConn:Disconnect(); return false,"tempo geral esgotado" end
                task.wait(.15)
                _,hum,root=parts()
                if not hum or not root then blockConn:Disconnect(); return false,"personagem indisponível" end
                if (root.Position-destination).Magnitude<=arrival then blockConn:Disconnect(); return true end
                if (root.Position-wp.Position).Magnitude<=2.5 then reached=true; break end
                if (root.Position-last).Magnitude<.25 then still+=.15 else still=0 end
                last=root.Position
                if blocked or still>=CONFIG.idleTimeout then break end
            end
            if not reached then repath=true; break end
        end
        blockConn:Disconnect()
        if not repath then
            local _,_,lastRoot=parts()
            if lastRoot and (lastRoot.Position-destination).Magnitude<=arrival then return true end
        end
        status("Recalculando rota ("..attempt.."/"..CONFIG.pathRetries..")")
        task.wait(.2)
    end
    return false,"rota bloqueada após tentativas"
end

local function interact(target)
    local prompt=target.prompt
    if not prompt or not prompt.Parent or not prompt.Enabled then return false,"prompt indisponível" end
    local _,_,root=parts()
    if not root or (root.Position-target.part.Position).Magnitude > prompt.MaxActivationDistance then
        return false,"fora do alcance da interação"
    end
    if carrying() then return true end
    local ok,err=pcall(function()
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration+.15)
        prompt:InputHoldEnd()
    end)
    if not ok then return false,"interação não executada: "..tostring(err) end
    local start=os.clock()
    while not state.stop and state.alive and os.clock()-start<CONFIG.collectionTimeout do
        if carrying() then return true end
        task.wait(.1)
    end
    return false,"coleta não confirmada pelo atributo Carrying"
end

local function execute()
    if state.busy then return end
    state.busy=true; state.stop=false
    local deadline=os.clock()+CONFIG.maxCycleSeconds
    local function done(s)
        status(s)
        state.busy=false
    end
    if carrying() then done("já está carregando um Exu"); return end
    if not ownPen() then done("base do jogador não identificada"); return end
    local targets=scan()
    if #targets==0 then done("nenhum Exu disponível"); return end
    local target=targets[1]
    state.selected=target
    targetLabel.Text=target.name.." | "..(target.official and "raridade " or "tamanho ")..target.detail
    status("Indo até: "..target.name)
    local approach=math.max(2, target.prompt.MaxActivationDistance-CONFIG.approachMargin)
    local ok,why=travel(target.part.Position,approach,deadline)
    if not ok then done("não alcançou alvo: "..why); return end
    if state.stop then done("cancelado"); return end
    status("Tentando coleta")
    local got,reason=interact(target)
    if not got then done(reason); return end
    status("Carregando; voltando à base")
    local destination=baseDestination()
    if not destination then done("não encontrou ponto da base"); return end
    ok,why=travel(destination,7,deadline)
    if not ok then done("retorno falhou: "..why); return end
    status("Na base; aguardando entrega normal")
    local before=inventory()
    local start=os.clock()
    while not state.stop and state.alive and os.clock()-start<CONFIG.deliveryTimeout do
        if not carrying() then
            local changed = inventory() ~= before
            done(changed and "descarregado; inventário mudou" or "descarregado; confirme a entrega")
            return
        end
        task.wait(.2)
    end
    done(state.stop and "cancelado" or "entrega não detectada")
end

button("ESCANEAR / SELECIONAR ALVO",function()
    local found=scan()
    if #found==0 then status("nenhum alvo encontrado"); return end
    local first=found[1]
    targetLabel.Text=first.name.." | "..(first.official and "raridade " or "tamanho ")..first.detail
    status(#found.." Exus encontrados; prioridade exibida")
end)
button("AUTO STEAL: 1 CICLO",function()
    if state.busy then status("ciclo já em execução"); return end
    task.spawn(function()
        local ok,err=pcall(execute)
        if not ok then state.busy=false; status("erro: "..tostring(err)) end
    end)
end)
button("PARAR",function()
    state.stop=true
    local _,hum,root=parts()
    if hum and root then hum:MoveTo(root.Position) end
    status("parada solicitada")
end)
button("FECHAR",function()
    state.stop=true; state.alive=false
    local _,hum,root=parts()
    if hum and root then hum:MoveTo(root.Position) end
    gui:Destroy()
end)

-- Drag with mouse for PC
local dragging=false; local dragStart; local startPosition
frame.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true; dragStart=input.Position; startPosition=frame.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
        local delta=input.Position-dragStart
        frame.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,
            startPosition.Y.Scale,startPosition.Y.Offset+delta.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
player:GetAttributeChangedSignal("PenName"):Connect(updateBase)
status("Hub pronto; repetição automática DESATIVADA")
