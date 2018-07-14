if mods.pyhightech then
  data.raw.recipe["train-scaling-stop"].ingredients = {
    {"train-stop", 1},
    {"locomotive", 1},
    {"electronic-circuit", 15},
  }
  data.raw.technology["train-scaling"].unit.ingredients[3] = nil
end
