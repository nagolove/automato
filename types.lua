local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; require("love")
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
require("mtschemes")

local inspect = require("inspect")

 Pos = {}




 Cell = {}

















 CellActions = {}

 CommonSetup = {}


































 CellSetup = {}






 Cells = {}
 Grid = {}
 GetGridFunction = {}
 InitCellFunction = {}

 CellActionsInit = {}











 Statistic = {}




















































 DrawNode = {}






 SimulatorMode = {}





 ThreadCommandsStore = {}










 ThreadCommands = {}


















formatMods = {
   ['allEated'] = '%d',
   ['maxEnergy'] = '%d',
   ['minEnergy'] = '%d',
   ['midEnergy'] = '%d',
   ['cells'] = '%d',
   ['iterations'] = '%d',
   ['meals'] = '%d',
   ['born'] = '%d',
   ['died'] = '%d',
   ['percentAreaFilled'] = '%f',
}

 Channels = {}

ChannelsTypes = {

   'setup',

   "cellrequest",

   "drawlist",

   "msg",

   "object",



   "request",

   "state",

   'stat',
   'isstopped',
}

function initChannels(n)
   local result = {}
   for _, v in ipairs(ChannelsTypes) do
      local name = v .. tostring(n)
      result[v] = love.thread.getChannel(name)
   end
   print('initChannels', inspect(result))
   return result
end

 Simulator = {Preset = {}, }
