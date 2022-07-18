-- Zone Capture Mod for Trailmakers --
-- developed by dinoman, ticibi 2022 --

local debug = false
local playerDataTable = {}
local ZoneStack = {}
local PlayerStack = {}
local timer = 0
local zoneScale = tm.vector3.Create(3, 10, 3)
local maxTeams = 4
local maxZones = 8
local zoneIndex = 1
local matchDuration = 60
local R = 10
local Models = {
    Ring = "PFB_MovePuzzleStart",
    Beam = "PFB_MovePuzzleTarget",
    Icon = "PFB_Beacon",
}
local Audio = {
    Woo = "LvlObj_ConfettiCelebration",
    Gong = "LvlObj_BlockHunt_begin",
    Blip = "LvlObj_BlockHunt_Beacon_callingSound",
}
local MatchData = {
    teams = {{id=1, score=0}},
    zones = {},
    matchDuration = matchDuration,
    matchTimer = matchDuration,
    captureRate = 1,
    repairPenalty = 50,
    gameActive = false,
    gameOver = false,
    gameReady = false,
    winningScore = 5000,
    winningTeam = 0,
    pointsPerSecond = 0.25,
    pointsPerCapture = 100,
}

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

function AddPlayerData(playerId)
    playerDataTable[playerId] = {
        localTimer = 0,
        globalTimer = 0,
        capturing = false,
        insideZone = false,
        ready = false,
        team = 0,
        zoneId = 0,
        stats = {
            zonesCaptured = 0,
            pointsEarned = 0,
        }
    }
end

function Test()
    table.insert(PlayerStack, {
        {name="moo", id=1},
        {name="meow", id=2},
        {name="woof", id=3},
        {name="point", id=4},
    })
    for i = 1, 4 do
        AddPlayerData(i)
    end
end

function AddKeybinds(player)
    local playerId = player.playerId
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "OnPlayerRepairVehicle", "r")
end

function onPlayerJoined(player)
    if debug then
        --Test()
        MatchData.captureRate = 2
        MatchData.pointsPerCapture = 100
        MatchData.pointsPerSecond = 0.25
        matchDuration = 60
    end
    AddPlayerData(player.playerId)
    table.insert(PlayerStack, {
        name=GetPlayerName(player.playerId),
        id=player.playerId
    })
    AddKeybinds(player)
    if MatchData.gameActive then
        playerDataTable[player.playerId].team = math.random(#MatchData.teams)
        MatchPage(player.playerId)
    else
        HomePage(player.playerId)
        for i, player in ipairs(PlayerStack) do
            HomePage(player.id)
        end
    end
end

function OnPlayerLeft(player)
    table.pop(PlayerStack, player.playerId)
    table.pop(playerDataTable, player.playerId)
end

tm.players.OnPlayerJoined.add(onPlayerJoined)
tm.players.OnPlayerLeft.add(OnPlayerLeft)

function update()
    local players = tm.players.CurrentPlayers()
    if MatchData.gameActive then
        for i, player in ipairs(players) do
            UpdateTimers()
            TestUpdatePlayerEnteredZone(player.playerId)
            TestUpdateZones()
            UpdateScores()
        end
    end
    timer = timer + 1
end

function TestUpdateZones()
    for i, zone in ipairs(ZoneStack) do
        if zone ~= nil then
            if #zone.players < 1 then
                if not zone.captured then
                    zone.value = 0
                    AnimateZoneCapture(zone, 0)
                end
                table.pop(ZoneStack, zone)
            end
            CaptureZone(zone, MatchData.captureRate)
        end
    end
end

function CaptureZone(zone, rate)
    local teamCount = CheckTeamCount(zone)
    if #teamCount > 1 then
        zone.contested = true
    else
        zone.contested = false
    end
    for i, playerId in ipairs(zone.players) do
        local playerData = playerDataTable[playerId]
        if not zone.contested then
            if playerData.team ~= zone.teamId then
                if not zone.captured then
                    if zone.value < 100 then
                        zone.value = zone.value + rate
                        SetValue(playerId, "banner", "Capturing Zone "..zone.id.." - "..zone.value.."%")
                        Broadcast("zone"..zone.id, "Zone "..zone.id.." is being Captured!")
                    else
                        zone.captured = true
                        local player = GetPlayer(playerId)
                        PlayAudio(Audio.Gong, player)
                        zone.teamId = playerData.team
                        local team = GetTeam(zone.teamId)
                        AddScore(team, MatchData.pointsPerCapture)
                        SetValue(playerId, "banner", "Zone "..zone.id.." controlled by Team "..zone.teamId)
                        Broadcast("zone"..zone.id, "Zone "..zone.id.." is Controlled by Team "..zone.teamId)
                    end
                elseif zone.captured then
                    if zone.value > 0 then
                        zone.value = zone.value - rate
                        if zone.value <= 0 then
                            zone.captured = false
                            zone.teamId = -1
                        end
                    end
                    SetValue(playerId, "banner", "Stealing Zone "..zone.id.." - "..zone.value.."%")
                    Broadcast("zone"..zone.id, "Zone "..zone.id.." is being Stolen!")
                end
            end
        else
        end
    end
    local ratio = zone.value / 100
    AnimateZoneCapture(zone, ratio)
end

function CheckTeamCount(zone)
    local teams = {}
    local counts = {}
    local output = {}
    for i, playerId in ipairs(zone.players) do
        local playerData = playerDataTable[playerId]
        if not table.contains(teams, playerData.team) then
            table.insert(teams, playerData.team)
            table.insert(counts, 1)
        elseif table.contains(teams, playerData) then
            counts[i] = counts[i] + 1
        end
    end
    for i = 1, #teams do
        table.insert(output, {teamId=teams[i], count=counts[i]})
    end
    return output
end

function AnimateZoneCapture(zone, ratio)
    local scale = tm.vector3.Create(
        zoneScale.x * ratio,
        zoneScale.y * ratio,
        zoneScale.z * ratio
    )
    zone.anim.GetTransform().SetScale(scale)
end

function TestUpdatePlayerEnteredZone(playerId)
    local playerPos = GetPlayerPos(playerId)
    local playerData = playerDataTable[playerId]
    for i, zone in ipairs(MatchData.zones) do
        local delta = tm.vector3.op_Subtraction(playerPos, zone.position)
        local magnitude = math.floor(math.abs(delta.Magnitude()))
        local radius = zone.scale.x * R
        if debug then
            SetValue(0, "debug zone #"..zone.id, "Zone #"..zone.id.." - "..magnitude.."m/"..radius)
        end
        if magnitude <= radius then
            if not playerData.insideZone then
                OnPlayerEnteredZone(playerId, zone)
                table.insertUnique(zone.players, playerId)
                table.insertUnique(ZoneStack, zone)
            end
        elseif magnitude > radius then
            if zone.id == playerData.zoneId then
                OnPlayerExitedZone(playerId, zone)
                table.pop(zone.players, playerId)
            end
        end
    end
end

function OnPlayerEnteredZone(playerId, zone)
    local playerData = playerDataTable[playerId]
    playerData.insideZone = true
    playerData.zoneId = zone.id
    local player = GetPlayer(playerId)
    PlayAudio(Audio.Blip, player)
    if playerData.team == zone.teamId then
        SetValue(playerId, "banner", "Your Team controls Zone "..zone.id)
    end
end

function OnPlayerExitedZone(playerId, zone)
    local playerData = playerDataTable[playerId]
    playerData.insideZone = false
    playerData.zoneId = 0
    SetValue(playerId, "banner", "Your are on Team "..playerData.team)
end

function UpdateScores()
    for i, zone in ipairs(MatchData.zones) do
        if zone.captured then
            local team = GetTeam(zone.teamId)
            AddScore(team, MatchData.pointsPerSecond)
        end
    end
end

function AddScore(team, score)
    team.score = team.score + score
    if team.score > MatchData.winningScore then
        MatchData.gameActive = false
        MatchData.gameOver = true
        GameOver()
        Broadcast("banner", "Team "..team.id.." reached "..MatchData.winningScore.." pts!")
    end
    Broadcast("team"..team.id, "Team "..team.id.." "..math.ceil(team.score).." pts")
end

function UpdatePlayerEnteredZone(playerId)
    local playerPos = GetPlayerPos(playerId)
    local playerData = playerDataTable[playerId]
    for i, zone in ipairs(MatchData.zones) do
        local delta = tm.vector3.op_Subtraction(playerPos, zone.position)
        local magnitude = math.floor(math.abs(delta.Magnitude()))
        local radius = zone.scale.x * R
        if magnitude < radius then
            playerData.zone = zone
            if zone.captured then
                if zone.team == playerData.team then
                    SetValue(playerId, "banner", "Zone "..zone.id.." Controlled by Team "..zone.team)
                else
                    zone.uncapture = true
                    zone.captured = false
                end
            end
            if not zone.occupied then
                if not playerData.capturing then
                    local player = GetPlayer(playerId)
                    PlayAudio(Audio.Gameover, player)
                    playerData.capturing = true
                end
            end
            zone.occupied = true
            zone.team = playerDataTable[playerId].team
            table.insertUnique(zone.players, playerId)
        else
            zone.occupied = false
            table.pop(zone.players, playerId)
            playerData.capturing = false
        end
    end
end

function UpdateTimers()
    if timer > 10 then
        timer = 0
        MatchData.matchTimer = MatchData.matchTimer - 1
        Broadcast("match time", MatchData.matchTimer.."s remaining")
        if MatchData.matchTimer <= 0 then
            GameOver()
        end
    end
end

function RemoveObjects()
    for i, zone in ipairs(MatchData.zones) do
        if isObjectValid(zone.object) then
            zone.object.Despawn()
        end
        if isObjectValid(zone.anim) then
            zone.anim.Despawn()
        end
        if isObjectValid(zone.beam) then
            zone.beam.Despawn()
        end
    end
end

function ResetMatchData()
    MatchData.gameActive = false
    MatchData.gameReady = false
    MatchData.gameOver = true
    MatchData.matchDuration = matchDuration
    MatchData.matchTimer = matchDuration
    MatchData.zones = {}
    MatchData.teams = {{id=1, score=0}}
    MatchData.winningTeam = 0
    zoneIndex = 1
    ZoneStack = {}
end

function GameOver()
    for i, _player in ipairs(PlayerStack) do
        local player = GetPlayer(_player.id)
        PlayAudio(Audio.Woo, player)
    end
    RemoveObjects()
    Broadcast("match time", "Match Ended!")
    Button(0, "play again", "play again", HomePage)
    ResetMatchData()
    ClearAllSpawns()
end

function GetTeam(teamId)
    for i, team in ipairs(MatchData.teams) do
        if team.id == teamId then
            return team
        end
    end
    return nil
end

function EvaluateScores()
    local scores = {}
    for i, team in ipairs(MatchData.teams) do
        table.insert(scores, team.score)
    end
    local highestScore = math.max(scores)
    for i, team in ipairs(MatchData.teams) do
        if team.score == highestScore then
            MatchData.winningTeam = team.id
        end
    end
end

function OnPlayerRepairVehicle(playerId)
    if not MatchData.gameActive then
        return
    end
    local playerData = playerDataTable[playerId]
    local team = GetTeam(playerData.team)
    AddScore(team, -MatchData.repairPenalty)
    SetValue(playerId, "status", "repaired vehicle -"..MatchData.repairPenalty.." pts")
end

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

function SetValue(playerId, key, text)
    tm.playerUI.SetUIValue(playerId, key, text)
end

function Broadcast(key, value)
    for i, player in ipairs(tm.players.CurrentPlayers()) do
        SetValue(player.playerId, key, value)
    end
end

function Clear(playerId)
    tm.playerUI.ClearUI(playerId)
end

function Label(playerId, key, text)
    tm.playerUI.AddUILabel(playerId, key, text)
end

function Divider(playerId)
    Label(playerId, "divider", "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬")
end

function Button(playerId, key, text, func)
    tm.playerUI.AddUIButton(playerId, key, text, func)
end

function PlayersList(playerId)
    for i, player in ipairs(PlayerStack) do
        local status = CheckReady(player.id)
        Label(playerId, "ready"..player.name, player.name..status)
    end
end

function HomePage(playerId)
    if type(playerId) ~= "number" then
        playerId = playerId.playerId
    end
    Clear(playerId)
    Label(playerId, "banner", "Waiting for host to setup match...")
    PlayersList(playerId)
    Button(playerId, "ready", "ready", OnReady)
    Button(playerId, "setup", "setup match", OnSetupMatch)
    if playerId == 0 then
        if MatchData.gameReady then
            SetValue(0, "setup", "edit setup")
            if CheckAllPlayersReady() then
                Button(playerId, "start", "start match!", OnStartMatch)
            else
                SetValue(playerId, "start", "waiting for players...")
            end
        end
    end
    Button(playerId, "start", "start match", OnStartMatch)
end

function MatchOptions(playerId)
    Button(playerId, "team count", "add team, max "..maxTeams.."; teams: "..#MatchData.teams, AddTeam)
    --Button(playerId, "zone scale", "zone scale", OnSetZoneScale)
    Button(playerId, "capture rate", "capture rate: "..MatchData.captureRate, OnSetCaptureRate)
    Button(playerId, "points per capture", "points per capture: "..MatchData.pointsPerCapture, OnSetPointsPerCapture)
    Button(playerId, "points per second", "points per second: "..MatchData.pointsPerSecond, OnSetPointsPerSecond)
    Button(playerId, "match duration", "match duration: "..MatchData.matchDuration, OnSetMatchDuration)
    Button(playerId, "repair penalty", "repair penalty: "..MatchData.repairPenalty, OnSetRepairPenalty)
    Button(playerId, "winning score", "winning score: "..MatchData.winningScore, OnSetWinningScore)
end

function OnSetCaptureRate(callback)
    MatchData.captureRate = MatchData.captureRate + 0.25
    if MatchData.captureRate > 2 then
        MatchData.captureRate = 0.25
    end
    SetValue(callback.playerId, "capture rate", "capture rate: "..MatchData.captureRate)
end

function OnSetZoneScale(callback)
    
end

function OnSetPointsPerCapture(callback)
    MatchData.pointsPerCapture = MatchData.pointsPerCapture + 100
    if MatchData.pointsPerCapture > 1000 then
        MatchData.pointsPerCapture = 100
    end
    SetValue(callback.playerId, "points per capture", "points per capture: "..MatchData.pointsPerCapture)
end

function OnSetPointsPerSecond(callback)
    MatchData.pointsPerSecond = MatchData.pointsPerSecond + 0.25
    if MatchData.pointsPerSecond > 2 then
        MatchData.pointsPerSecond = 0.25
    end
    SetValue(callback.playerId, "points per second", "points per second: "..MatchData.pointsPerSecond)
end

function OnSetMatchDuration(callback)
    matchDuration = matchDuration + 30
    if matchDuration > 300 then
        matchDuration = 60
    end
    MatchData.matchDuration = matchDuration
    MatchData.matchTimer = matchDuration
    SetValue(callback.playerId, "match duration", "match duration: "..MatchData.matchDuration)
end

function OnSetRepairPenalty(callback)
    MatchData.repairPenalty = MatchData.repairPenalty + 50
    if MatchData.repairPenalty > 250 then
        MatchData.repairPenalty = 50
    end
    SetValue(callback.playerId, "repair penalty", "repair penalty: "..MatchData.repairPenalty)
end

function OnSetWinningScore(callback)
    MatchData.winningScore = MatchData.winningScore + 500
    if MatchData.winningScore > 5000 then
        MatchData.winningScore = 1000
    end
    SetValue(callback.playerId, "winning score", "winning score: "..MatchData.winningScore)
end

function OnSetupMatch(callback)
    local playerId = callback.playerId
    Clear(playerId)
    MatchOptions(playerId)
    Divider(playerId)
    for i, zone in ipairs(MatchData.zones) do
        Button(playerId, "zone "..zone.id, "relocate Zone "..zone.id, MoveZone)
    end
    if #MatchData.zones == maxZones then
        Button(playerId, "place zone", "max Zones placed", OnPlaceZone)
    else
        Button(playerId, "place zone", "place Zone "..#MatchData.zones + 1, OnPlaceZone)
    end
    Divider(playerId)
    Button(playerId, "finish", "finish setup", OnFinishSetup)
end

function SpawnZone(pos)
    local offset = tm.vector3.Create(0, 1, 0)
    local spawnPos = tm.vector3.op_Addition(pos, offset)
    local object = Spawn(spawnPos, Models.Ring)
    object.GetTransform().SetScale(zoneScale)
    local anim = Spawn(spawnPos, Models.Ring)
    anim.GetTransform().SetScale(0)
    local beam = Spawn(spawnPos, Models.Icon)
    beam.GetTransform().SetScale(0.5)
    AddZone(object, anim, beam, spawnPos, zoneScale, zoneIndex)
    zoneIndex = zoneIndex + 1
end

function AddZone(object, anim, beam, pos, scale, id)
    table.insert(MatchData.zones, {
        id=id,
        object=object,
        anim=anim,
        beam=beam,
        position=pos,
        scale=scale,
        players={},
        captured=false,
        occupied=false,
        contested=false,
        score=0,
        value=0,
        teamId=0,
    }
    )
end

function SetZoneScale(zoneId, scale)
    for i, zone in ipairs(MatchData.zones) do
        if tonumber(zone.id) == tonumber(zoneId) then
            if isObjectValid(zone.object) then
                zone.object.GetTransform().SetScale(scale)
            end
        end
    end
end

function UpdateZonePosition(zone, pos)
    zone.position = pos
    if isObjectValid(zone.object) then
        zone.object.GetTransform().SetPosition(zone.position)
    end
    if isObjectValid(zone.anim) then
        zone.anim.GetTransform().SetPosition(zone.position)
    end
    if isObjectValid(zone.beam) then
        zone.beam.GetTransform().SetPosition(zone.position)
    end
end

function MoveZone(callback)
    local playerPos = GetPlayerPos(callback.playerId)
    local offset = tm.vector3.Create(0, 1, 0)
    local pos = tm.vector3.op_Addition(playerPos, offset)
    local zoneId = tonumber(string.slice(callback.id, 5))
    local zone = GetZoneById(zoneId)
    if zone == nil then
        return
    end
    UpdateZonePosition(zone, pos)
end

function GetZoneById(zoneId)
    for i, zone in ipairs(MatchData.zones) do
        if tonumber(zone.id) == tonumber(zoneId) then
            return zone
        end
    end
end

function ZoneWidget(playerId)
    for i, zone in ipairs(MatchData.zones) do
        Label(playerId, "zone"..zone.id, "Zone "..zone.id.." Uncontrolled")
    end
end

function TeamWidget(playerId)
    for i, team in ipairs(MatchData.teams) do
        Label(playerId, "team"..team.id, "Team "..team.id.." "..team.score.." pts")
    end
end

function DebugZoneWidget(playerId)
    for i, zone in ipairs(MatchData.zones) do
        Label(0, "debug zone #"..zone.id, "Zone "..zone.id.." - ".."0 : 0")
    end
end

function MatchPage(playerId)
    local playerData = playerDataTable[playerId]
    Clear(playerId)
    Label(playerId, "banner", "You are on Team #"..playerData.team)
    Label(playerId, "match time", MatchData.matchTimer.."s remaining")
    Divider(playerId)
    ZoneWidget(playerId)
    Divider(playerId)
    TeamWidget(playerId)
    Divider(playerId)
    Label(playerId, "status1", "repair vehicle -"..MatchData.repairPenalty.." pts")
    Label(playerId, "status2", "capture +"..MatchData.pointsPerCapture.." pts")
    Label(playerId, "status3", "hold zone +"..(MatchData.pointsPerSecond * 8).." pts/second")
    if debug then
        Button(0, "switch teams", "switch teams", OnSwitchTeams)
        DebugZoneWidget(0)
    end
end

function OnSwitchTeams(callback)
    local playerData = playerDataTable[callback.playerId]
    if playerData.team + 1 > #MatchData.teams then
        playerData.team = 1
    else
        playerData.team = playerData.team + 1
    end
    SetValue(callback.playerId, "banner", "You are on Team "..playerData.team)
end

function AssignTeams()
    for i, player in ipairs(tm.players.CurrentPlayers()) do
        playerDataTable[player.playerId].team = math.random(#MatchData.teams)
    end
end

function AddTeam(callback)
    if #MatchData.teams + 1 > maxTeams then
        return
    end
    table.insert(MatchData.teams, {id=#MatchData.teams + 1, score=0})
    SetValue(callback.playerId, "team count", "add team - teams: "..#MatchData.teams)
    OnSetupMatch(callback)
end

function OnFinishSetup(callback)
    MatchData.gameReady = true
    if #MatchData.zones < 1 then
        SetValue(callback.playerId, "finish", "Cannot start without zones")
        return
    end
    HomePage(callback.playerId)
end

function OnPlaceZone(callback)
    local playerId = callback.playerId
    if #MatchData.zones >= maxZones then
        return
    end
    local playerPos = GetPlayerPos(playerId)
    SpawnZone(playerPos)
    if #MatchData.zones + 1 > maxZones then
        SetValue(playerId, "place zone", "placed max zones")
    else
        SetValue(playerId, "place zone", "place zone #"..#MatchData.zones + 1)
    end
    OnSetupMatch(callback)
end

function CheckReady(playerId)
    local playerData = playerDataTable[playerId]
    if not playerData.ready then
        return " (not ready)"
    end
    return " (ready)"
end

function OnReady(callback)
    local playerId = callback.playerId
    playerDataTable[playerId].ready = not playerDataTable[playerId].ready
    if playerDataTable[playerId].ready then
        SetValue(playerId, "ready", "unready")
    else
        SetValue(playerId, "ready", "ready")
    end
    for i, player in ipairs(PlayerStack) do
        local status = CheckReady(player.id)
        Broadcast("ready"..player.name, player.name..status)
    end
end

function CheckAllPlayersReady()
    for i, player in ipairs(tm.players.CurrentPlayers()) do
        if not playerDataTable[player.playerId].ready then
            return false
        end
    end
    return true
end

function OnStartMatch(callback)
    if not MatchData.gameReady then
        return
    end
    MatchData.gameActive = true
    AssignTeams()
    MatchData.gameReady = false
    for i, player in ipairs(tm.players.CurrentPlayers()) do
        MatchPage(player.playerId)
    end
end

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

function ClearAllSpawns()
    tm.physics.ClearAllSpawns()
end

function PlayAudio(cue, player)
    tm.audio.PlayAudioAtGameobject(cue, player)
end

function GetPlayer(playerId)
    return tm.players.GetPlayerGameObject(playerId)
end

function Spawn(pos, model)
    return tm.physics.SpawnObject(pos, model)
end

function ReadDynamicFile(path)
    local file = tm.os.ReadAllText_Dynamic(path)
    if isFileValid(file) then
        return json.parse(file)
    end
end

function WriteDynamicFile(path, data)
    local jsonData = json.serialize(data)
    tm.os.WriteAllText_Dynamic(path, jsonData)
end

function GetPlayerPos(playerId)
    return tm.players.GetPlayerTransform(playerId).GetPosition()
end

function GetPlayerName(playerId)
    return tm.players.GetPlayerName(playerId)
end

function CreateRandomizedVector(limitX, limitY, limitZ, value)
    value = value or 0.1
    return tm.vector3.Create(
        math.random(-limitX, limitX) * value,
        math.random(-limitY, limitY) * value,
        math.random(-limitZ, limitZ) * value
    )
end

function isEmpty(_table)
    return _table == {} or #_table < 1
end

function isFileValid(file)
    return file ~= nil and file ~= ""
end

function isObjectValid(object)
    return object.Exists() and object ~= nil
end

function VectorToTable(vector)
    return {
        x = vector.x,
        y = vector.y,
        z = vector.z
    }
end

function TableToVector(table)
    return tm.vector3.Create(table.x, table.y, table.z)
end

function PrintVector(vector)
    return 'x: '..vector.x..', y: '..vector.y..', z: '..vector.z
end

function Log(text)
    tm.os.log(text)
end

function GetDeltaTime()
    return tm.os.GetModDeltaTime()
end

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

-- returns index of item
function table.index(_table, _item)
    if _table == nil or _table == {} then
        return
    end
    for i, v in ipairs(_table) do
        if _item == v then
            return i
        end
    end
end

-- removes item from table if it exists
function table.pop(_table, _item)
    if _table == nil or _table == {} then
        return
    end
    if not table.contains(_table, _item) then return end
    for i, v in ipairs(_table) do
        if _item == v then
            table.remove(_table, i)
        end
    end
end

-- checks if item is in table
function table.contains(_table, _item)
    if _table == nil or _table == {} then
        return
    end
    for _, v in ipairs(_table) do
        if _item == v then
            return true
        end
    end
    return false
end

-- overwrites item in table if item already exists, or appends item
function table.overwrite(_table, _item)
    if _table == nil or _table == {} then
        return
    end
    if table.contains(_table, _item) then
        local index = table.index(_table, _item)
        if index ~= nil then
            _table[index] = _item
        end
    else
        table.insert(_table, _item)
    end
end

-- returns a reversed copy of a table
function table.reversed(_table)
    if _table == nil or _table == {} then
        return
    end
    local copy = _table
    local len = #copy
    local i = 1
    while i < len do
        copy[i], copy[len] = copy[len], copy[i]
        i = i + 1
        len = len - 1
    end
    return copy
end

-- inserts item into table if not in table already
function table.insertUnique(_table, _item)
    if _table == nil or _table == {} then
        return
    end
    if table.contains(_table, _item) then
        return
    end
    table.insert(_table, _item)
end

-- returns the last element of a table
function table.last(_table)
    if _table == nil or _table == {} then
        return
    end
    if #_table < 1 then
        error('table empty', 2)
    end
    return _table[#_table]
end

-- splits string by delimiter
function string.split(_string, delimiter)
    if type(_string) ~= "string" then
        return
    end
    delimiter = delimiter or '%S+'
    local output = {}
    for char in string.gmatch(_string, '%S+') do
        table.insert(output, char)
    end
    return output
end

function table.find(_table, _item)
    if _table == nil or _table == {} then
        return
    end
    for i, item in ipairs(_table) do
        if item == _item then
            return item
        end
    end
    return nil
end

function string.slice(string, n)
    if type(string) ~= "string" then
        return
    end
    return string:sub(n, #string)
end
