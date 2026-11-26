-- Detector quente/frio com Bluetooth real (cai para simulação se não houver BLE)
-- Papéis: PROCURADOR (apita) e ESCONDEDOR (emite sinal)

local state = "menu"          -- "menu" | "seeker" | "hider"
local W, H
local fBig, fMed, fSmall
local beep
local beepTimer = 0
local flash = 0
local pulse = 0
local now = 0

local simDist = 0.8           -- só para o modo simulação
local rssiSmooth = -90
local history = {}
local HIST_SIZE = 6
local dragging = false

local btnSeeker, btnHider, btnBack, slider

-- ponte Bluetooth (módulo Java fala com o Lua por UDP local)
local socket_ok, socket = pcall(require, "socket")
local rx, tx
local bleReal = false
local bleStatus = "Sem Bluetooth (modo simulação)"
local lastHello = -100
local lastRssiTime = -100
local dbgMsg = ""

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function inside(r, x, y)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function pushHistory(v)
  table.insert(history, v)
  if #history > HIST_SIZE then table.remove(history, 1) end
end

local function initNet()
  if not socket_ok then return end
  local ok = pcall(function()
    rx = socket.udp()
    assert(rx:setsockname("127.0.0.1", 9876))
    rx:settimeout(0)
    tx = socket.udp()
    tx:settimeout(0)
  end)
  if not ok then rx, tx = nil, nil end
end

local function sendCmd(c)
  if tx then pcall(tx.sendto, tx, c, "127.0.0.1", 9877) end
end

local function pollNet()
  if not rx then return end
  while true do
    local msg = rx:receive()
    if not msg then break end
    if msg == "hello" then
      lastHello = now; bleStatus = "Bluetooth pronto"
    elseif msg == "btoff" then
      lastHello = now; bleStatus = "Ligue o Bluetooth"
    elseif msg:sub(1, 4) == "dbg " then
      dbgMsg = msg:sub(5); lastHello = now
    elseif msg:sub(1, 5) == "rssi " then
      local v = tonumber(msg:sub(6))
      if v then
        lastHello = now
        if state == "seeker" then pushHistory(v); lastRssiTime = now end
      end
    end
  end
  bleReal = (now - lastHello) < 3
  if not bleReal then bleStatus = "Sem Bluetooth (modo simulação)" end
end

local function makeBeep()
  local rate, dur = 44100, 0.06
  local n = math.floor(rate * dur)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local env = math.min(1, i / (n * 0.05), (n - i) / (n * 0.3))
    sd:setSample(i, math.sin(2 * math.pi * 880 * (i / rate)) * 0.6 * env)
  end
  return love.audio.newSource(sd)
end

local function layout()
  W, H = love.graphics.getDimensions()
  fBig = love.graphics.newFont(math.floor(H * 0.045))
  fMed = love.graphics.newFont(math.floor(H * 0.03))
  fSmall = love.graphics.newFont(math.floor(H * 0.022))
  local bw, bh = W * 0.8, H * 0.13
  btnSeeker = { x = W * 0.1, y = H * 0.38, w = bw, h = bh }
  btnHider  = { x = W * 0.1, y = H * 0.58, w = bw, h = bh }
  btnBack   = { x = W * 0.03, y = H * 0.03, w = W * 0.22, h = H * 0.06 }
  slider    = { x = W * 0.1, y = H * 0.88, w = W * 0.8, h = H * 0.05 }
end

local function simRSSI()
  return -40 - simDist * 50 + (math.random() - 0.5) * 8
end

local function goMenu()
  state = "menu"
  sendCmd("stop")
end

local function updateSeeker(dt)
  if bleReal then
    if now - lastRssiTime > 3 then history = { -95 } end
  else
    pushHistory(simRSSI())
  end
  if #history > 0 then
    local sum = 0
    for _, v in ipairs(history) do sum = sum + v end
    rssiSmooth = sum / #history
  end

  local prox = clamp((rssiSmooth + 90) / 50, 0, 1)
  local interval = lerp(1.5, 0.08, prox)

  beepTimer = beepTimer + dt
  if beepTimer >= interval then
    beepTimer = 0
    beep:stop()
    beep:setPitch(lerp(0.7, 1.6, prox))
    beep:play()
    flash = 1
  end
  flash = math.max(0, flash - dt * 5)
end

function love.load()
  math.randomseed(os.time())
  layout()
  beep = makeBeep()
  initNet()
end

function love.resize() layout() end

function love.update(dt)
  now = love.timer.getTime()
  pulse = pulse + dt
  pollNet()
  if state == "seeker" then updateSeeker(dt) end
end

local function drawButton(r, label, color)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 20, 20)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(fMed)
  love.graphics.printf(label, r.x, r.y + r.h / 2 - fMed:getHeight() / 2, r.w, "center")
end

local function drawBack()
  love.graphics.setColor(0.25, 0.25, 0.3)
  love.graphics.rectangle("fill", btnBack.x, btnBack.y, btnBack.w, btnBack.h, 12, 12)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(fSmall)
  love.graphics.printf("< Voltar", btnBack.x, btnBack.y + btnBack.h / 2 - fSmall:getHeight() / 2, btnBack.w, "center")
end

local function drawMenu()
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(fBig)
  love.graphics.printf("Detector", 0, H * 0.15, W, "center")
  love.graphics.setFont(fSmall)
  love.graphics.setColor(0.7, 0.7, 0.75)
  love.graphics.printf("Escolha seu papel", 0, H * 0.25, W, "center")
  drawButton(btnSeeker, "PROCURADOR", { 0.15, 0.45, 0.85 })
  drawButton(btnHider, "ESCONDEDOR", { 0.8, 0.3, 0.25 })
  love.graphics.setColor(bleReal and 0.4 or 0.8, bleReal and 0.9 or 0.7, 0.4)
  love.graphics.setFont(fSmall)
  love.graphics.printf(bleStatus, 0, H * 0.85, W, "center")
  love.graphics.setColor(1, 0.9, 0.4)
  love.graphics.printf(dbgMsg, W * 0.05, H * 0.89, W * 0.9, "center")
  love.graphics.setColor(0.5, 0.5, 0.55)
  love.graphics.printf("lua v6", 0, H * 0.96, W, "center")
end

local function drawHider()
  drawBack()
  local cx, cy = W / 2, H * 0.42
  for i = 0, 2 do
    local t = (pulse * 0.6 + i / 3) % 1
    love.graphics.setColor(0.8, 0.3, 0.25, 1 - t)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", cx, cy, W * 0.08 + t * W * 0.35)
  end
  love.graphics.setColor(0.8, 0.3, 0.25)
  love.graphics.circle("fill", cx, cy, W * 0.08)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(fBig)
  love.graphics.printf("ESCONDEDOR", 0, H * 0.7, W, "center")
  love.graphics.setFont(fSmall)
  love.graphics.setColor(0.75, 0.75, 0.8)
  love.graphics.printf("Seu celular está emitindo o sinal.\nEsconda ele e não faça barulho!", W * 0.1, H * 0.78, W * 0.8, "center")
  love.graphics.printf(bleStatus, 0, H * 0.9, W, "center")
  love.graphics.setColor(1, 0.9, 0.4)
  love.graphics.printf(dbgMsg, W * 0.05, H * 0.95, W * 0.9, "center")
end

local function drawSeeker()
  drawBack()
  local prox = clamp((rssiSmooth + 90) / 50, 0, 1)
  local cx, cy = W / 2, H * 0.36
  local r, g, b = lerp(0.15, 0.95, prox), lerp(0.45, 0.2, prox), lerp(0.9, 0.15, prox)

  love.graphics.setColor(r, g, b, 0.25 + flash * 0.4)
  love.graphics.circle("fill", cx, cy, W * 0.2 + flash * W * 0.12)
  love.graphics.setColor(r, g, b)
  love.graphics.circle("fill", cx, cy, W * 0.14 + flash * W * 0.03)

  local label = "Frio"
  if prox > 0.85 then label = "FERVENDO!"
  elseif prox > 0.6 then label = "Quente"
  elseif prox > 0.3 then label = "Morno" end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(fBig)
  love.graphics.printf(label, 0, H * 0.57, W, "center")
  love.graphics.setFont(fSmall)
  love.graphics.setColor(0.75, 0.75, 0.8)
  local info
  if bleReal and now - lastRssiTime > 3 then
    info = "Procurando o escondedor..."
  else
    info = string.format("Sinal: %d dBm", math.floor(rssiSmooth))
  end
  love.graphics.printf(info, 0, H * 0.65, W, "center")
  love.graphics.printf("PROCURADOR", 0, H * 0.1, W, "center")
  love.graphics.setColor(1, 0.9, 0.4)
  love.graphics.printf(dbgMsg, W * 0.05, H * 0.72, W * 0.9, "center")

  if not bleReal then
    love.graphics.setColor(0.6, 0.6, 0.65)
    love.graphics.printf("Simular distância (arraste)", 0, slider.y - H * 0.05, W, "center")
    love.graphics.setColor(0.25, 0.25, 0.3)
    love.graphics.rectangle("fill", slider.x, slider.y + slider.h / 2 - 4, slider.w, 8, 4, 4)
    love.graphics.setColor(r, g, b)
    love.graphics.circle("fill", slider.x + simDist * slider.w, slider.y + slider.h / 2, slider.h * 0.6)
    love.graphics.setColor(0.6, 0.6, 0.65)
    love.graphics.printf("perto", slider.x, slider.y + slider.h + 6, slider.w, "left")
    love.graphics.printf("longe", slider.x, slider.y + slider.h + 6, slider.w, "right")
  end
end

function love.draw()
  love.graphics.clear(0.08, 0.08, 0.1)
  if state == "menu" then drawMenu()
  elseif state == "hider" then drawHider()
  else drawSeeker() end
end

local function setSlider(x)
  simDist = clamp((x - slider.x) / slider.w, 0, 1)
end

function love.mousepressed(x, y)
  if state == "menu" then
    if inside(btnSeeker, x, y) then
      state = "seeker"; history = {}; beepTimer = 0
      sendCmd("seeker")
    elseif inside(btnHider, x, y) then
      state = "hider"
      sendCmd("hider")
    end
    return
  end
  if inside(btnBack, x, y) then goMenu(); return end
  if state == "seeker" and not bleReal
     and y > slider.y - slider.h and y < slider.y + slider.h * 2 then
    dragging = true
    setSlider(x)
  end
end

function love.mousemoved(x, y)
  if dragging then setSlider(x) end
end

function love.mousereleased() dragging = false end

function love.keypressed(key)
  if key == "escape" then
    if state == "menu" then love.event.quit() else goMenu() end
  end
end
