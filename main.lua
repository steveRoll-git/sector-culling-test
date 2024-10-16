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

local function dist(x1, y1, x2, y2)
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

local function normalize(x, y)
  local len = dist(0, 0, x, y)
  return x / len, y / len
end

local function dot(x1, y1, x2, y2)
  return x1 * x2 + y1 * y2
end

local function rotatePoint(x, y, angle)
  return x * math.cos(angle) - y * math.sin(angle), y * math.cos(angle) + x * math.sin(angle)
end

local mapWidth = 20
local mapHeight = 20
local tileSize = 24

local map = {}

---@type Sector[]
local sectors = {}

---@type table<Sector, true>
local visibleSectors = {}

---@type table<number, Sector>
local sectorsLookup = {}

local painting = false
local paintValue

local draggingCamera = false

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

local oppositeDirections = {
  [directionsNamed.left] = directionsNamed.right,
  [directionsNamed.right] = directionsNamed.left,
  [directionsNamed.up] = directionsNamed.down,
  [directionsNamed.down] = directionsNamed.up,
}

local camera = {
  x = mapWidth / 2,
  y = mapHeight / 2,
  lookX = 1,
  lookY = 0,
  leftLookX = 0,
  leftLookY = 0,
  rightLookX = 0,
  rightLookY = 0,
  fov = math.rad(100)
}

local function setCameraLook(x, y)
  camera.lookX, camera.lookY = x, y
  camera.leftLookX, camera.leftLookY = rotatePoint(camera.lookX, camera.lookY, -camera.fov / 2 + math.pi / 2)
  camera.rightLookX, camera.rightLookY = rotatePoint(camera.lookX, camera.lookY, camera.fov / 2 - math.pi / 2)
end

setCameraLook(1, 0)

do
  local d = tileSize * 3
  local verts = { { 0, 0, 1, 1, 1, 1 } }
  for a = -camera.fov / 2, camera.fov / 2, camera.fov / 4 do
    table.insert(verts, {
      math.cos(a) * d,
      math.sin(a) * d,
      1, 1, 1, 0
    })
  end
  camera.mesh = lg.newMesh({
    { "VertexPosition", "float", 2 },
    { "VertexColor",    "float", 4 },
  }, verts, "fan")
end

local moveKeys = {
  w = { y = -1 },
  s = { y = 1 },
  a = { x = -1 },
  d = { x = 1 },
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

---@class SectorLink
---@field x1 number
---@field y1 number
---@field x2 number
---@field y2 number
---@field sector Sector

---@class Sector
---@field x1 number
---@field y1 number
---@field x2 number
---@field y2 number
---@field color table
---@field links table<Direction, SectorLink[]>
---@field planes table<Direction, {x: number, y: number}>
---@field visitDirX? number
---@field visitDirY? number
---@field _cameFrom Sector?

local function newSector(x1, y1, x2, y2)
  ---@type Sector
  local new = {
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
    color = { HSVToRGB(#sectors / 12, 0.7, 1, 0.6) },
    links = {},
    planes = {},
  }
  return new
end

---@param s1 Sector
---@param s2 Sector
---@param direction Direction
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
local function linkSectors(s1, s2, direction, x1, y1, x2, y2)
  if not s1.links[direction] then
    s1.links[direction] = {}
  end
  table.insert(s1.links[direction], {
    x1 = x1,
    x2 = x2,
    y1 = y1,
    y2 = y2,
    sector = s2
  })
  if not s2.links[oppositeDirections[direction]] then
    s2.links[oppositeDirections[direction]] = {}
  end
  table.insert(s2.links[oppositeDirections[direction]], {
    x1 = x1,
    x2 = x2,
    y1 = y1,
    y2 = y2,
    sector = s1
  })
end

local function generateSectors()
  sectors = {}
  sectorsLookup = {}

  local function isEmpty(x, y)
    return not getTile(x, y) and not sectorsLookup[id(x, y)]
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
      if sectorsLookup[id(x, y)] then
        goto continue
      elseif not getTile(x, y) then
        local new = newSector(x, y, x, y)
        sectorsLookup[id(x, y)] = new

        -- expand along the x axis
        while inMap(new.x2 + 1, new.y2) and isEmpty(new.x2 + 1, new.y2) do
          new.x2 = new.x2 + 1
          sectorsLookup[id(new.x2, new.y2)] = new
        end

        -- expand along the y axis
        while inMap(new.x2, new.y2 + 1) and isRowEmpty(x, new.x2, new.y2 + 1) do
          new.y2 = new.y2 + 1
          for x3 = x, new.x2 do
            sectorsLookup[id(x3, new.y2)] = new
          end
        end

        new.planes = {
          [directionsNamed.left] = {
            x = new.x1,
            y = new.y1,
          },
          [directionsNamed.right] = {
            x = new.x2 + 1,
            y = new.y1,
          },
          [directionsNamed.up] = {
            x = new.x1,
            y = new.y1,
          },
          [directionsNamed.down] = {
            x = new.x1,
            y = new.y2 + 1,
          },
        }

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
        if inMap(x, s.y1 - 1) and sectorsLookup[id(x, s.y1 - 1)] then
          local other = sectorsLookup[id(x, s.y1 - 1)]
          if lastLeft == other then
            goto continue
          end
          local x1, x2 = math.max(s.x1, other.x1), math.min(s.x2, other.x2) + 1
          local y = s.y1
          linkSectors(s, other, directionsNamed.up, x1, y, x2, y)
          lastLeft = other
        end
        ::continue::
      end
    end

    if s.x1 > 0 then
      -- look for sectors directly to the left of `s`, and link them together.
      local lastUp
      for y = s.y1, s.y2 do
        if inMap(s.x1 - 1, y) and sectorsLookup[id(s.x1 - 1, y)] then
          local other = sectorsLookup[id(s.x1 - 1, y)]
          if lastUp == other then
            goto continue
          end
          local y1, y2 = math.max(s.y1, other.y1), math.min(s.y2, other.y2) + 1
          local x = s.x1
          linkSectors(s, other, directionsNamed.left, x, y1, x, y2)
          lastUp = other
        end
        ::continue::
      end
    end
  end
end

local function pointOutsideLeftFrustum(x, y)
  return dot(x, y, camera.leftLookX, camera.leftLookY) < dot(camera.x, camera.y, camera.leftLookX, camera.leftLookY)
end

local function pointOutsideRightFrustum(x, y)
  return dot(x, y, camera.rightLookX, camera.rightLookY) < dot(camera.x, camera.y, camera.rightLookX, camera.rightLookY)
end

local function calculateVisibility()
  visibleSectors = {}

  if not inMap(math.floor(camera.x), math.floor(camera.y)) then
    return
  end

  -- Sectors added to this queue will be marked visible,
  -- and their neighbors will be checked.
  ---@type Sector[]
  local queue = {}

  local initialSector = sectorsLookup[id(math.floor(camera.x), math.floor(camera.y))]
  if not initialSector then
    return
  end
  initialSector.visitDirX = nil
  initialSector.visitDirY = nil
  visibleSectors[initialSector] = true
  table.insert(queue, initialSector)

  while #queue > 0 do
    ---@type Sector
    local s = table.remove(queue, 1)

    for dir, links in pairs(s.links) do
      -- If `s` has been visited from a certain direction, we ignore links opposite to that direction.
      if s.visitDirX and ((dir.x ~= 0 and s.visitDirX == -dir.x) or (dir.y ~= 0 and s.visitDirY == -dir.y)) then
        goto continue
      end

      local plane = s.planes[dir]
      -- If the camera is behind this direction's plane, we ignore all links in this direction.
      if dot(plane.x, plane.y, dir.x, dir.y) < dot(camera.x, camera.y, dir.x, dir.y) then
        goto continue
      end

      for _, link in ipairs(links) do
        local next = link.sector
        -- If we haven't already marked this sector visible, and the link is inside the camera's frustum,
        -- mark it visible and add it to the queue.
        if
            not visibleSectors[next] and
            not (
              (pointOutsideLeftFrustum(link.x1, link.y1) and pointOutsideLeftFrustum(link.x2, link.y2)) or
              (pointOutsideRightFrustum(link.x1, link.y1) and pointOutsideRightFrustum(link.x2, link.y2))) then
          visibleSectors[next] = true
          table.insert(queue, next)
          next._cameFrom = s
          -- Store which x and y direction we visited this sector from.
          next.visitDirX = dir.x ~= 0 and dir.x or (s.visitDirX or 0)
          next.visitDirY = dir.y ~= 0 and dir.y or (s.visitDirY or 0)
        end
      end
      ::continue::
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
    calculateVisibility()
  end
end

function love.mousepressed(x, y, btn)
  if btn == 1 then
    if dist(x, y, camera.x * tileSize, camera.y * tileSize) <= 10 then
      draggingCamera = true
    else
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
end

function love.mousemoved(x, y, dx, dy)
  if draggingCamera then
    camera.x = camera.x + dx / tileSize
    camera.y = camera.y + dy / tileSize
    calculateVisibility()
  elseif painting then
    paint(math.floor(x / tileSize), math.floor(y / tileSize), paintValue)
  end
end

function love.mousereleased(x, y, btn)
  if draggingCamera and btn == 1 then
    draggingCamera = false
  elseif painting and btn == 1 then
    painting = false
  end
end

function love.update(dt)
  local moved = false
  if love.mouse.isDown(2) then
    local mx, my = love.mouse.getPosition()
    local cx, cy = camera.x * tileSize, camera.y * tileSize
    if mx ~= cx or my ~= cy then
      setCameraLook(normalize(mx - cx, my - cy))
      moved = true
    end
  end
  for key, dir in pairs(moveKeys) do
    if love.keyboard.isDown(key) then
      camera.x = camera.x + (dir.x or 0) * 6 * dt
      camera.y = camera.y + (dir.y or 0) * 6 * dt
      moved = true
    end
  end
  if moved then
    calculateVisibility()
  end
end

function love.draw()
  lg.setColor(1, 1, 1, 0.4)
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
    lg.setColor(s.color[1], s.color[2], s.color[3], s.color[4] * (visibleSectors[s] and 1 or 0.4))
    lg.rectangle("fill", s.x1 * tileSize + margin, s.y1 * tileSize + margin, (s.x2 - s.x1 + 1) * tileSize - margin * 2,
      (s.y2 - s.y1 + 1) * tileSize - margin * 2)
  end

  lg.setLineWidth(3)
  lg.setLineStyle("rough")
  for _, s in ipairs(sectors) do
    local l = 6
    for dir, links in pairs(s.links) do
      for _, link in ipairs(links) do
        local isVisible = visibleSectors[s] and visibleSectors[link.sector] and
            (s._cameFrom == link.sector or link.sector._cameFrom == s)
        if isVisible then
          lg.push()
          lg.translate((link.x1 + link.x2) / 2 * tileSize, (link.y1 + link.y2) / 2 * tileSize)
          lg.rotate(math.atan2(dir.y, dir.x))
          lg.setColor(1, 1, 1)
          lg.line(-l, 0, l, 0)
          lg.pop()
        end
      end
    end
  end

  lg.push()
  lg.translate(camera.x * tileSize, camera.y * tileSize)
  lg.rotate(math.atan2(camera.lookY, camera.lookX))
  lg.setColor(1, 1, 1, 0.1)
  lg.arc("fill", 0, 0, 800, -camera.fov / 2, camera.fov / 2)
  lg.setColor(1, 1, 1)
  lg.circle("fill", 0, 0, tileSize / 4)
  lg.setColor(1, 1, 1, 0.8)
  lg.draw(camera.mesh)
  lg.pop()
end
