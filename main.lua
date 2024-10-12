io.stdout:setvbuf("no")

local IS_DEBUG = arg[2] == "debug" and not love.filesystem.isFused()
if IS_DEBUG and os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  require("lldebugger").start()

  function love.errorhandler(msg)
    error(msg, 2)
  end
end

local love = love
local lg = love.graphics

local mapWidth = 20
local mapHeight = 20
local tileSize = 24

local map = {}

---@type Sector[]
local sectors = {}

local painting = false
local paintValue

---@class Direction
---@field x number
---@field y number

---@type table<string, Direction>
local directionsNamed = {
  right = { x = 1, y = 0 },
  left = { x = -1, y = 0 },
  down = { x = 0, y = 1 },
  up = { x = 0, y = -1 },
}

---@type Direction[]
local directions = {
  directionsNamed.right,
  directionsNamed.left,
  directionsNamed.up,
  directionsNamed.down,
}

local function id(x, y)
  return y * mapWidth + x
end

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

---@class Sector
---@field x1 number
---@field y1 number
---@field x2 number
---@field y2 number
---@field color table
---@field links table<Direction, Sector[]>

local function newSector(x1, y1, x2, y2)
  ---@type Sector
  local new = {
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
    color = { HSVToRGB(#sectors / 12, 0.7, 1, 0.75) },
    links = {}
  }
  for _, d in ipairs(directions) do
    new.links[d] = {}
  end
  return new
end

local function generateSectors()
  sectors = {}

  ---@type table<number, Sector>
  local sectorifiedPositions = {}

  local function isEmpty(x, y)
    return not getTile(x, y) and not sectorifiedPositions[id(x, y)]
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
      if sectorifiedPositions[id(x, y)] then
        goto continue
      elseif not getTile(x, y) then
        local new = newSector(x, y, x, y)
        sectorifiedPositions[id(x, y)] = new

        -- expand along the x axis
        while inMap(new.x2 + 1, new.y2) and isEmpty(new.x2 + 1, new.y2) do
          new.x2 = new.x2 + 1
          sectorifiedPositions[id(new.x2, new.y2)] = new
        end

        -- expand along the y axis
        while inMap(new.x2, new.y2 + 1) and isRowEmpty(x, new.x2, new.y2 + 1) do
          new.y2 = new.y2 + 1
          for x3 = x, new.x2 do
            sectorifiedPositions[id(x3, new.y2)] = new
          end
        end

        table.insert(sectors, new)
      end
      ::continue::
    end
  end

  for _, s in ipairs(sectors) do
    -- look for sectors directly above `s`, and link them together.
    if s.y1 > 0 then
      local lastLeft
      for x = s.x1, s.x2 do
        if inMap(x, s.y1 - 1) and sectorifiedPositions[id(x, s.y1 - 1)] then
          local other = sectorifiedPositions[id(x, s.y1 - 1)]
          if lastLeft == other then
            goto continue
          end
          table.insert(s.links[directionsNamed.up], other)
          table.insert(other.links[directionsNamed.down], s)
          lastLeft = other
        end
        ::continue::
      end
    end

    if s.x1 > 0 then
      -- look for sectors directly to the left of `s`, and link them together.
      local lastUp
      for y = s.y1, s.y2 do
        if inMap(s.x1 - 1, y) and sectorifiedPositions[id(s.x1 - 1, y)] then
          local other = sectorifiedPositions[id(s.x1 - 1, y)]
          if lastUp == other then
            goto continue
          end
          table.insert(s.links[directionsNamed.left], other)
          table.insert(other.links[directionsNamed.right], s)
          lastUp = other
        end
        ::continue::
      end
    end
  end
end

local function paint(x, y, value)
  if not inMap(x, y) then
    return
  end
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
  lg.setLineWidth(1)
  lg.setLineStyle("rough")

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

  lg.setColor(1, 0, 0)
  lg.setLineWidth(3)
  lg.setLineStyle("rough")
  for _, s in ipairs(sectors) do
    local l = 6
    for _, other in ipairs(s.links[directionsNamed.left]) do
      local y = (math.max(s.y1, other.y1) + math.min(s.y2, other.y2) + 1) / 2 * tileSize
      lg.line(s.x1 * tileSize - l, y, s.x1 * tileSize + l, y)
    end
    for _, other in ipairs(s.links[directionsNamed.up]) do
      local x = (math.max(s.x1, other.x1) + math.min(s.x2, other.x2) + 1) / 2 * tileSize
      lg.line(x, s.y1 * tileSize - l, x, s.y1 * tileSize + l)
    end
  end
end
