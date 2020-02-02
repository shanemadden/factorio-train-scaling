local util = require('util')

local item = {
  type = "item",
  name = "train-scaling-stop",
  icon = "__train-scaling__/graphics/icons/train-scaling-stop.png",
  icon_size = 32,
  flags = {},
  subgroup = "transport",
  order = "a[train-system]-cz[train-scaling-stop]",
  place_result = "train-scaling-stop",
  stack_size = 10
}

local recipe = {
  type = "recipe",
  name = "train-scaling-stop",
  enabled = false,
  ingredients = {
    {"train-stop", 1},
    {"locomotive", 1},
    {"advanced-circuit", 15},
  },
  result = "train-scaling-stop"
}

local technology = {
  type = "technology",
  name = "train-scaling",
  icon_size = 128,
  icon = "__base__/graphics/technology/railway.png",
  effects = {
    {
      type = "unlock-recipe",
      recipe = "train-scaling-stop"
    }
  },
  prerequisites = { "rail-signals", "advanced-electronics" },
  unit = {
    count = 500,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
    },
    time = 30
  },
  order = "c-g-c-z"
}

local entity = util.table.deepcopy(data.raw["train-stop"]["train-stop"])
entity.name = "train-scaling-stop"
entity.color = {r = 1, g = 0.45, b = 0, a = 0.8}
entity.icon = "__train-scaling__/graphics/icons/train-scaling-stop.png"
entity.icon_size = 32
entity.minable.result = "train-scaling-stop"

local player = util.table.deepcopy(data.raw["character"]["character"])
player.name = "train-scaling-driver"
player.collision_mask = {"ghost-layer"}

local signal_group = {
  type = "item-subgroup",
  name = "train-scaling-signal",
  group = "signals",
  order = "z[train-scaling-signal]"
}

local up_signal = {
  type = "virtual-signal",
  name = "signal-train-scale-up",
  icon = "__train-scaling__/graphics/icons/signal-train-scale-up.png",
  icon_size = 32,
  subgroup = "train-scaling-signal",
  order = "a[special]-a[train-scale-up]"
}

local down_signal = {
  type = "virtual-signal",
  name = "signal-train-scale-down",
  icon = "__train-scaling__/graphics/icons/signal-train-scale-down.png",
  icon_size = 32,
  subgroup = "train-scaling-signal",
  order = "a[special]-b[train-scale-down]"
}

data:extend({ item, recipe, entity, player, technology, signal_group, up_signal, down_signal })
