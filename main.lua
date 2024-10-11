local love = love
local lg = love.graphics

local mapWidth = 20
local mapHeight = 20
local tileSize = 24

local map = {}

local sectors = {}

local painting = false
local paintValue

local function HSVToRGB(h, s, v, a)
  local w = ((h % 1) * 6)
  local c = v * s
  local x = c * (1 - math.abs(w % 2 - 1))
  local m = v - c
  local r, g, b = m, m, m
  if w < 1 then
    r = r + c
    g = g + x
  elseif w < 2 then
    r = r + x
    g = g + c
  elseif w < 3 then
    g = g + c
    b = b + x
  elseif w < 4 then
    g = g + x
    b = b + c
  elseif w < 5 then
    b = b + c
    r = r + x
  else
    b = b + x
    r = r + c
  end
  return r, g, b, a
end

local function inMap(x, y)
  return x >= 0 and x < mapWidth and y >= 0 and y < mapHeight
end

local function getTile(x, y)
  return map[y * mapWidth + x]
end

local function generateSectors()
  sectors = {}

  local sectorifiedPositions = {}

  local function isEmpty(x, y)
    return not getTile(x, y) and not sectorifiedPositions[y * mapWidth + x]
  end

  local function isRowEmpty(x1, x2, y)
    for x = x1, x2 do
      if not isEmpty(x, y) then
        return false
      end
    end
    return true
  end

  for y = 0, mapHeight - 1 do
    for x = 0, mapWidth - 1 do
      if sectorifiedPositions[y * mapWidth + x] then
        goto continue
      elseif not getTile(x, y) then
        local x2, y2 = x, y
        while inMap(x2 + 1, y2) and isEmpty(x2 + 1, y2) do
          x2 = x2 + 1
          sectorifiedPositions[y2 * mapWidth + x2] = true
        end
        while y2 + 1 < mapHeight and isRowEmpty(x, x2, y2 + 1) do
          y2 = y2 + 1
          for x3 = x, x2 do
            sectorifiedPositions[y2 * mapWidth + x3] = true
          end
        end
        table.insert(sectors, { x1 = x, y1 = y, x2 = x2, y2 = y2, color = { HSVToRGB(#sectors / 12, 0.7, 1, 0.75) } })
      end
      ::continue::
    end
  end
end

local function paint(x, y, value)
  local prev = map[y * mapHeight + x]
  map[y * mapHeight + x] = value
  if value ~= prev then
    generateSectors()
  end
end

function love.mousepressed(x, y, btn)
  if btn == 1 then
    local mx = math.floor(love.mouse.getX() / tileSize)
    local my = math.floor(love.mouse.getY() / tileSize)
    if inMap(mx, my) then
      local prev = map[my * mapWidth + mx]
      paintValue = not prev
      paint(mx, my, paintValue)
      painting = true
    end
  end
end

function love.mousemoved(x, y, dx, dy)
  if painting then
    paint(math.floor(x / tileSize), math.floor(y / tileSize), paintValue)
  end
end

function love.mousereleased(x, y, btn)
  if painting and btn == 1 then
    painting = false
  end
end

function love.draw()
  lg.setColor(1, 1, 1, 0.5)
  for y = 0, mapHeight - 1 do
    local dy = y * tileSize
    lg.line(0, dy, mapWidth * tileSize, dy)
  end
  for x = 0, mapWidth - 1 do
    local dx = x * tileSize
    lg.line(dx, 0, dx, mapHeight * tileSize)
  end
  for y = 0, mapHeight - 1 do
    for x = 0, mapWidth - 1 do
      local tile = getTile(x, y)
      if tile then
        lg.setColor(1, 1, 1)
        lg.rectangle("fill", x * tileSize, y * tileSize, tileSize, tileSize)
      end
    end
  end
  for _, s in ipairs(sectors) do
    local margin = 2
    lg.setColor(s.color)
    lg.rectangle("fill", s.x1 * tileSize + margin, s.y1 * tileSize + margin, (s.x2 - s.x1 + 1) * tileSize - margin * 2,
      (s.y2 - s.y1 + 1) * tileSize - margin * 2)
  end
end
