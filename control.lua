require('util')

-- geometry helpers
local rotate_relative_position = {
  [defines.direction.north] = function(x, y)
    return x, y
  end,
  [defines.direction.east] = function(x, y)
    return y * -1, x
  end,
  [defines.direction.south] = function(x, y)
    return x * -1, y * -1
  end,
  [defines.direction.west] = function(x, y)
    return y, x * -1
  end,
}
local in_cone = {
  [defines.direction.north] = function(orientation)
    if orientation >= 0.875 or orientation < 0.125 then
      return true
    end
  end,
  [defines.direction.east] = function(orientation)
    if orientation >= 0.125 and orientation < 0.375 then
      return true
    end
  end,
  [defines.direction.south] = function(orientation)
    if orientation >= 0.375 and orientation < 0.625 then
      return true
    end
  end,
  [defines.direction.west] = function(orientation)
    if orientation >= 0.625 and orientation < 0.875 then
      return true
    end
  end,
}
local opposite = {
  [defines.direction.north] = defines.direction.south,
  [defines.direction.east] = defines.direction.west,
  [defines.direction.south] = defines.direction.north,
  [defines.direction.west] = defines.direction.east,
}

-- comparison funtion to determine if two carriages are configured the same for all attributes we care to compare
local function carriage_eq(carriage_a, carriage_b)
  -- compare color
  if carriage_a.color or carriage_b.color then
    if not carriage_a.color or not carriage_b.color then
      return false
    end
    if carriage_a.color.r ~= carriage_a.color.r or carriage_a.color.g ~= carriage_a.color.g or carriage_a.color.b ~= carriage_a.color.b or carriage_a.color.a ~= carriage_a.color.a then
      return false
    end
  end
  -- same entity
  if carriage_a.name ~= carriage_b.name then
    return false
  end
  local inventory_a = carriage_a.get_inventory(defines.inventory.cargo_wagon)
  local inventory_b = carriage_b.get_inventory(defines.inventory.cargo_wagon)
  -- inventory barring and filtering
  if inventory_a then
    if inventory_a.hasbar() then
      if not inventory_b.hasbar() or inventory_a.getbar() ~= inventory_b.getbar() then
        return false
      end
    elseif inventory_b.hasbar() then
      return false
    end
    if inventory_a.supports_filters() and inventory_a.is_filtered() then
      for i = 1, #inventory_a do
        if inventory_a.get_filter(i) ~= inventory_b.get_filter(i) then
          return false
        end
      end
    elseif inventory_b.supports_filters() and inventory_b.is_filtered() then
      return false
    end
  end
  -- grid
  if carriage_a.grid and carriage_a.grid.valid then
    if not carriage_b.grid or not carriage_b.grid.valid then
      return false
    else
      -- different count
      if #carriage_a.grid.equipment ~= #carriage_b.grid.equipment then
        return false
      end

      local equip_locations = {}
      for _, equipment in ipairs(carriage_a.grid.equipment) do
        equip_locations[string.format("%d,%d", equipment.position.x, equipment.position.y)] = equipment.name
      end
      for _, equipment in ipairs(carriage_b.grid.equipment) do
        local pos_str = string.format("%d,%d", equipment.position.x, equipment.position.y)
        if not equip_locations[pos_str] or not equip_locations[pos_str] == equipment.name then
          return false
        end
      end
    end
  elseif carriage_b.grid and carriage_b.grid.valid then
    return false
  end
  return true
end

-- compare two trains to see if they're configured the same
local function train_eq(train_a, train_b)
  -- same train?
  if train_a.id == train_b.id then
    return true
  end
  -- different length?
  if #train_a.carriages ~= #train_b.carriages then
    return false
  end
  -- compare schedules
  if train_a.schedule and train_b.schedule then
    local train_a_records = train_a.schedule.records
    local train_b_records = train_b.schedule.records
    if #train_a_records ~= #train_b_records then
      return false
    end
    for i, record in ipairs(train_a_records) do
      if record.station == train_b_records[i].station then
        local train_b_conditions = train_b_records[i].wait_conditions
        for j, condition in ipairs(record.wait_conditions) do
          if condition.type ~= train_b_conditions[j].type then
            return false
          end
          if condition.compare_type ~= train_b_conditions[j].compare_type then
            return false
          end
          if condition.ticks and condition.ticks ~= train_b_conditions[j].ticks then
            return false
          end
          if condition.condition then
            local condition_a = condition.condition
            local condition_b = train_b_conditions[j].condition
            if condition_a.comparator and condition_a.comparator ~= condition_b.comparator then
              return false
            end
            if condition_a.constant and condition_a.constant ~= condition_b.constant then
              return false
            end
            if condition_a.first_signal then
              if not condition_b.first_signal then
                return false
              end
              if condition_a.first_signal.type ~= condition_b.first_signal.type then
                return false
              end
              if condition_a.first_signal.name ~= condition_b.first_signal.name then
                return false
              end
            end
            if condition_a.second_signal then
              if not condition_b.second_signal then
                return false
              end
              if condition_a.second_signal.type ~= condition_b.second_signal.type then
                return false
              end
              if condition_a.second_signal.name ~= condition_b.second_signal.name then
                return false
              end
            end
          end
        end
      else
        return false
      end
    end
  else
    -- one has no schedule, make sure both do
    if train_a.schedule or train_b.schedule then
      return false
    end
  end
  --compare carriages
  -- collect info about which way both trains' locos face
  local a_forward = {}
  for _, v in ipairs(train_a.locomotives.front_movers) do
    a_forward[v.unit_number] = true
  end
  local a_backward = {}
  for _, v in ipairs(train_a.locomotives.back_movers) do
    a_backward[v.unit_number] = true
  end
  local b_forward = {}
  for _, v in ipairs(train_b.locomotives.front_movers) do
    b_forward[v.unit_number] = true
  end
  local b_backward = {}
  for _, v in ipairs(train_b.locomotives.back_movers) do
    b_backward[v.unit_number] = true
  end
  -- try carriages facing the same way
  local match = true
  local train_b_carriages = train_b.carriages
  for i, carriage_a in ipairs(train_a.carriages) do
    local carriage_b = train_b_carriages[i]
    if carriage_a.type == "locomotive" then
      if a_forward[carriage_a.unit_number] and not b_forward[carriage_b.unit_number] then
        match = false
        break
      end
      if a_backward[carriage_a.unit_number] and not b_backward[carriage_b.unit_number] then
        match = false
        break
      end
    end
    if not carriage_eq(carriage_a, carriage_b) then
      match = false
      break
    end
  end
  if match then
    return true
  end

  -- try carriages facing the opposite way
  for i, carriage_a in ipairs(train_a.carriages) do
    local carriage_b = train_b_carriages[#train_b_carriages-(i-1)]
    if carriage_a.type == "locomotive" then
      if a_forward[carriage_a.unit_number] and not b_backward[carriage_b.unit_number] then
        return false
      end
      if a_backward[carriage_a.unit_number] and not b_forward[carriage_b.unit_number] then
        return false
      end
    end
    if not carriage_eq(carriage_a, carriage_b) then
      return false
    end
  end

  return true
end

-- check if a carriage is attached to a train, for checking placement validity
local function carriage_in_train(carriage, train)
  local found = false
  for _, check_carriage in ipairs(train.carriages) do
    if check_carriage.unit_number == carriage.unit_number then
      -- the carriage attached to the right train
      found = true
      break
    end
  end
  return found
end

-- when station entities are created, add to tracking as appropriate
local default_backer_names
local function on_built_entity(event)
  if event.created_entity.type == "train-stop" then
    if event.created_entity.backer_name == "__mt__" then
      return
    end
    local entity = event.created_entity
    if event.created_entity.name == "train-scaling-stop" then
      -- do this only if it's a default name
      if not default_backer_names then
        -- haven't called this yet, scan once and cache in local table
        default_backer_names = {}
        for _, backer_name in pairs(game.backer_names) do
          default_backer_names[backer_name] = true
        end
      end
      if default_backer_names[entity.backer_name] then
        entity.backer_name = "Train Scaling Station"
      end
      -- add chest ghosts
      local x_input, y_input = rotate_relative_position[entity.direction](1.5, 0.5)
      local x_output, y_output = rotate_relative_position[entity.direction](1.5, -0.5)
      if entity.surface.can_place_entity({
        name = "logistic-chest-requester",
        position = {
          x = entity.position.x + x_input,
          y = entity.position.y + y_input,
        },
        force = entity.force,
        build_check_type = defines.build_check_type.ghost_place,
      }) then
        local requester = entity.surface.create_entity({
          name = "entity-ghost",
          inner_name = "logistic-chest-requester",
          position = {
            x = entity.position.x + x_input,
            y = entity.position.y + y_input,
          },
          force = entity.force,
        })
        if requester and requester.valid then
          requester.last_user = entity.last_user
        end
      end
      if entity.surface.can_place_entity({
        name = "logistic-chest-active-provider",
        position = {
          x = entity.position.x + x_output,
          y = entity.position.y + y_output,
        },
        force = entity.force,
        build_check_type = defines.build_check_type.ghost_place,
      }) then
        local provider = entity.surface.create_entity({
          name = "entity-ghost",
          inner_name = "logistic-chest-active-provider",
          position = {
            x = entity.position.x + x_output,
            y = entity.position.y + y_output,
          },
          force = entity.force,
        })
        if provider and provider.valid then
          provider.last_user = entity.last_user
        end
      end

      global.scaling_stations[entity.surface.index][entity.force.name][entity.backer_name].entities[entity.unit_number] = entity
    elseif global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] then
      global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].entities[entity.unit_number] = entity
    end
  end
end
script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)

-- update entity registration on rename
local function on_entity_renamed(event)
  if event.entity.name == "train-scaling-stop" then
    local entity = event.entity
    -- unregister the entity from tracking in the old table
    if event.old_name ~= "__mt__" then
      global.scaling_stations[entity.surface.index][entity.force.name][event.old_name].entities[entity.unit_number] = nil

      -- check if the old station name no longer has any associated stations
      if not next(global.scaling_stations[entity.surface.index][entity.force.name][event.old_name].entities)then
        -- delete its config if that was the last
        global.scaling_stations[entity.surface.index][entity.force.name][event.old_name] = nil
      end
    end
    if entity.backer_name == "__mt__" then
      return
    end
    -- register the entity for tracking in the new table
    global.scaling_stations[entity.surface.index][entity.force.name][entity.backer_name].entities[entity.unit_number] = entity
  elseif event.entity.type == "train-stop" then
    local entity = event.entity
    if event.old_name ~= "__mt__" and global.enabled_stations[entity.surface.index][entity.force.name][event.old_name] and global.enabled_stations[entity.surface.index][entity.force.name][event.old_name].entities then
      -- unregister the entity from tracking in the old table
      global.enabled_stations[entity.surface.index][entity.force.name][event.old_name].entities[entity.unit_number] = nil
      -- check if the old station name no longer has any associated stations
      if not next(global.enabled_stations[entity.surface.index][entity.force.name][event.old_name].entities) then
        -- that was the last one
        -- check if new name is unconfigured, if it is we'll move the config over
        if not global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] or not global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].entities then
          global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] = global.enabled_stations[entity.surface.index][entity.force.name][event.old_name]
        end
        -- remove old config
        global.enabled_stations[entity.surface.index][entity.force.name][event.old_name] = nil
      end

      if entity.backer_name == "__mt__" then
        return
      end
      -- register in new table if it's already set up
      if global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] and global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].entities then
        global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].entities[entity.unit_number] = entity
      end

    else
      if entity.backer_name == "__mt__" then
        return
      end
      if global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] and global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].entities then
        -- new name is configured but old wasn't, just register
        global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].entities[entity.unit_number] = entity
      end
    end
  end
end
script.on_event(defines.events.on_entity_renamed, on_entity_renamed)

-- remove entity registrations when they're removed
local function on_entity_gone(event)
  if event.entity.name == "train-scaling-stop" then
    -- nil this station's settings and metrics
    global.scaling_stations[event.entity.surface.index][event.entity.force.name][event.entity.backer_name].entities[event.entity.unit_number] = nil
    global.scaling_station_metrics[event.entity.unit_number] = nil
    global.scaling_burner_state[event.entity.unit_number] = nil

    -- if it was the last of these, nuke the config table too
    if not next(global.scaling_stations[event.entity.surface.index][event.entity.force.name][event.entity.backer_name].entities) then
      global.scaling_stations[event.entity.surface.index][event.entity.force.name][event.entity.backer_name] = nil
    end
  elseif event.entity.type == "train-stop" then
    if global.enabled_stations[event.entity.surface.index][event.entity.force.name][event.entity.backer_name] then
      -- unregister from tracking
      global.enabled_stations[event.entity.surface.index][event.entity.force.name][event.entity.backer_name].entities[event.entity.unit_number] = nil
      global.scaling_signal_holdoff_timestamps[event.entity.unit_number] = nil

      -- if it was the last of these, nuke the config table too
      if not next(global.enabled_stations[event.entity.surface.index][event.entity.force.name][event.entity.backer_name].entities) then
        global.enabled_stations[event.entity.surface.index][event.entity.force.name][event.entity.backer_name] = nil
      end
    end
  end
end
script.on_event(defines.events.on_robot_pre_mined, on_entity_gone)
script.on_event(defines.events.on_pre_player_mined_item, on_entity_gone)
script.on_event(defines.events.on_entity_died, on_entity_gone)

local function on_forces_merging(event)
  -- deconflicting templates and all that is a hassle, just nil out the source side's configs for now
  for _, surface in pairs(game.surfaces) do
    global.scaling_stations[surface.index][event.source.name] = nil
    global.enabled_stations[surface.index][event.source.name] = nil
  end
end
script.on_event(defines.events.on_forces_merging, on_forces_merging)

local function on_pre_surface_deleted(event)
  global.scaling_stations[event.surface_index] = nil
  global.enabled_stations[event.surface_index] = nil
end
script.on_event(defines.events.on_pre_surface_deleted, on_pre_surface_deleted)

-- scan a wagon's equipment grid, make a table representation of it
local function grid_to_table(grid)
  if not grid or not grid.valid then
    return
  end
  local grid_table = {}
  for i, equipment in ipairs(grid.equipment) do
    grid_table[i] = {
      name = equipment.name,
      position = equipment.position,
      item_name = equipment.prototype.take_result.name,
    }
  end
  return grid_table
end

-- table representations of carriages for construction
local carriage_to_table = {
  ["locomotive"] = function(carriage, reverse)
    local color
    if carriage.color then
      color = {
        r = carriage.color.r,
        g = carriage.color.g,
        b = carriage.color.b,
        a = carriage.color.a,
      }
    end
    local fuel_categories
    if carriage.burner then
      fuel_categories = carriage.burner.fuel_categories
    end
    return {
      name = carriage.name,
      color = color,
      reverse = reverse,
      type = "locomotive",
      fuel_categories = fuel_categories,
      grid = grid_to_table(carriage.grid),
    }
  end,
  ["cargo-wagon"] = function(carriage)
    local t = {
      name = carriage.name,
      type = "cargo-wagon",
      grid = grid_to_table(carriage.grid),
    }
    local inventory = carriage.get_inventory(defines.inventory.cargo_wagon)
    if inventory.hasbar() then
      t.bar = inventory.getbar()
    end
    if inventory.supports_filters() and inventory.is_filtered() then
      t.filter = {}
      for i = 1, #inventory do
        t.filter[i] = inventory.get_filter(i)
      end
    end
    return t
  end,
  ["fluid-wagon"] = function(carriage)
    return {
      name = carriage.name,
      type = "fluid-wagon",
      grid = grid_to_table(carriage.grid),
    }
  end,
  -- these are directional, try to figure out a good way to determine template's facing?
  ["artillery-wagon"] = function(carriage)
    return {
      name = carriage.name,
      type = "artillery-wagon",
      grid = grid_to_table(carriage.grid),
    }
  end,
}

-- placement functions for each wagon type
local try_place_wagon = {
  ["locomotive"] = function(train_config, carriage_config)
    local direction
    if carriage_config.reverse then
      direction = opposite[train_config.direction]
    else
      direction = train_config.direction
    end
    local loco = train_config.builder_loco.surface.create_entity({
      name = carriage_config.name,
      position = train_config.position,
      direction = direction,
      force = train_config.builder_loco.force,
    })
    if loco then
      if carriage_config.color then
        loco.color = carriage_config.color
      end
    end
    return loco
  end,
  ["cargo-wagon"] = function(train_config, carriage_config)
    local wagon = train_config.builder_loco.surface.create_entity({
      name = carriage_config.name,
      position = train_config.position,
      direction = train_config.direction,
      force = train_config.builder_loco.force,
    })
    if not wagon then
      return
    end
    if carriage_config.bar or carriage_config.filter then
      local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
      if not inventory or not inventory.valid then
        return wagon
      end
      if carriage_config.bar then
        inventory.setbar(carriage_config.bar)
      end
      if carriage_config.filter then
        for slot, filter in pairs(carriage_config.filter) do
          inventory.set_filter(slot, filter)
        end
      end
    end
    return wagon
  end,
  ["fluid-wagon"] = function(train_config, carriage_config)
    return train_config.builder_loco.surface.create_entity({
      name = carriage_config.name,
      position = train_config.position,
      direction = train_config.direction,
      force = train_config.builder_loco.force,
    })
  end,
  ["artillery-wagon"] = function(train_config, carriage_config)
    return train_config.builder_loco.surface.create_entity({
      name = carriage_config.name,
      position = train_config.position,
      direction = train_config.direction,
      force = train_config.builder_loco.force,
    })
  end,
}

-- helpers for when deconstructing trains
local function clear_inventory_into_inventory(inventory_to_clear, dest_inventory)
  if not inventory_to_clear or not inventory_to_clear.valid or not dest_inventory or not dest_inventory.valid then
    return
  end
  for item_name, count in pairs(inventory_to_clear.get_contents()) do
    if dest_inventory.can_insert({ name = item_name, count = count }) then
      dest_inventory.insert({
        name = item_name,
        count = inventory_to_clear.remove({
          name = item_name,
          count = count,
        })
      })
    else
      return
    end
  end
end

local function deconstruct_carriage_into_inventory(carriage, inventory)
  -- clear its grid, clear its fuel, step through the products array of the entity's mineable_properties and add them to the chest
  if not carriage or not carriage.valid then
    return
  end
  if not inventory or not inventory.valid then
    return
  end
  if carriage.burner then
    clear_inventory_into_inventory(carriage.burner.inventory, inventory)
    clear_inventory_into_inventory(carriage.burner.burnt_result_inventory, inventory)
  end
  if carriage.grid and carriage.grid.valid then
    for _, equipment in ipairs(carriage.grid.equipment) do
      local item = carriage.grid.take({
        equipment = equipment,
      })
      if inventory.can_insert({ name = item.name, count = item.count }) then
        inventory.insert({
          name = item.name,
          count = item.count,
        })
      else
        return
      end
    end
  end
  -- shouldn't have cargo but let's clear it anyway
  clear_inventory_into_inventory(carriage.get_inventory(defines.inventory.cargo_wagon), inventory)

  for _, product in ipairs(carriage.prototype.mineable_properties.products) do
    if product.type == "item" then
      if inventory.can_insert({ name = product.name, count = 1 }) then
        inventory.insert({
          name = product.name,
          count = 1,
        })
      else
        return
      end
    end
  end
  -- raise event for other mods tracking their carriages before destroying
  script.raise_event(defines.events.script_raised_destroy, {entity = carriage})
  carriage.destroy()
  return true
end

local function abort_remove_carriage(carriage_config, inventory)
  -- cleaning up leftover carriages from a failed build, need to make sure they delete even if there's no inventory
  local entity = carriage_config.built_wagon
  if inventory and inventory.valid then
    -- fuel
    local fuel_inventory = entity.get_inventory(defines.inventory.fuel)
    for item_name, item_count in pairs(fuel_inventory.get_contents()) do
      inventory.insert({
        name = item_name,
        count = item_count,
      })
      fuel_inventory.remove({
        name = item_name,
        count = item_count,
      })
    end

    -- grid
    if entity.grid and entity.grid.valid then
      for _, equipment in ipairs(entity.grid.equipment) do
        local item = entity.grid.take({
          equipment = equipment,
        })
        if inventory.can_insert({ name = item.name, count = item.count }) then
          inventory.insert({
            name = item.name,
            count = item.count,
          })
        end
      end
    end

    -- the wagon itself
    inventory.insert({
      name = carriage_config.item_to_place,
      count = 1,
    })
  end
  -- raise event for other mods tracking their carriages before destroying
  script.raise_event(defines.events.script_raised_destroy, {entity = entity})
  entity.destroy()
end

local function abort_build(train_config)
  -- tearing down this entire train since the build failed for some reason
  if train_config.driver and train_config.driver.valid then
    train_config.driver.destroy()
  end
  if train_config.builder_loco and train_config.builder_loco.valid then
    -- save the state of the tug train's burner for next time this station builds one
    local burner = train_config.builder_loco.burner
    global.scaling_burner_state[train_config.builder_station_unit_number] = {
      currently_burning = burner.currently_burning,
      remaining_burning_fuel = burner.remaining_burning_fuel,
      inventory_contents = burner.inventory.get_contents(),
    }
    train_config.builder_loco.destroy()
  end
  local inventory
  if train_config.input_chest.valid then
    inventory = train_config.input_chest.get_inventory(defines.inventory.chest)
  end
  -- destroy all carriages
  for _, carriage_config in ipairs(train_config) do
    if carriage_config.built_wagon and carriage_config.built_wagon.valid then
      abort_remove_carriage(carriage_config, inventory)
    end
  end
  -- clear from queue
  global.scaling_build_queue[train_config.builder_station_unit_number] = nil
  local station_config = global.enabled_stations[train_config.surface_index][train_config.force_name][train_config.enabled_station_name]
  if station_config.running_builds and station_config.running_builds > 0 then
    station_config.running_builds = station_config.running_builds - 1
  else
    station_config.running_builds = 0
  end
  -- unregister if there's no other pending builds
  if not next(global.scaling_build_queue) then
    script.on_nth_tick(5, nil)
  end
end

local function abort_deconstruct(train_config)
  if train_config.driver and train_config.driver.valid then
    train_config.driver.destroy()
  end
  if train_config.builder_loco and train_config.builder_loco.valid then
    -- save the state of the tug train's burner for next time this station builds one
    local burner = train_config.builder_loco.burner
    global.scaling_burner_state[train_config.builder_station_unit_number] = {
      currently_burning = burner.currently_burning,
      remaining_burning_fuel = burner.remaining_burning_fuel,
      inventory_contents = burner.inventory.get_contents(),
    }
    train_config.builder_loco.destroy()
  end
  -- clear from queue
  global.scaling_build_queue[train_config.builder_station_unit_number] = nil
  if not next(global.scaling_build_queue) then
    script.on_nth_tick(5, nil)
  end
end

local function total_position_diff(entity_a, entity_b)
  return math.abs(entity_a.position.x - entity_b.position.x) + math.abs(entity_a.position.y - entity_b.position.y) 
end

-- tick handler (once every 5 ticks) which is registered only while a train is constructing/deconstructing
local function building_tick(event)
  for i, train_config in pairs(global.scaling_build_queue) do
    local abort = false
    local train
    -- bail if the tug's gone
    if not train_config.builder_loco.valid then
      abort = true
      if train_config.builder_station.valid then
        train_config.builder_station.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-construction-train-missing"},
          position = train_config.builder_station.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = train_config.builder_station.force,
        })
      end
    else
      train = train_config.builder_loco.train
      -- bail if the station's gone
      if not train_config.builder_station.valid then
        abort = true
        train_config.builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-construction-station-missing"},
          position = train_config.builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = train_config.builder_loco.force,
        })
      end
      -- bail if the length isn't what we expect due to attaching to another train or deleting cars
      if #train.carriages ~= train_config.expected_length then
        abort = true
        train_config.builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-wrong-train-length"},
          position = train_config.builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = train_config.builder_loco.force,
        })
      end
      -- bail if there hasn't been a carriage successfully placed in 15 seconds
      if game.tick - train_config.progress_tick > 900 then
        abort = true
        train_config.builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-timeout"},
          position = train_config.builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = train_config.builder_loco.force,
        })
      end
    end
    -- we're through the generic error checks, now branch based on what type of job is being done
    if train_config.type == "construction" then
      if not train_config.template or not train_config.template.valid then
        abort = true
        train_config.builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-train-wrong-configuration"},
          position = train_config.builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = train_config.builder_loco.force,
        })
      end
      if not train_config.input_chest or not train_config.input_chest.valid then
        abort = true
        train_config.builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-input-chest-missing"},
          position = train_config.builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = train_config.builder_loco.force,
        })
      end

      if abort then
        abort_build(train_config)
      else
        -- set the direction of stepping on the gas depending on which way the tug is "facing" on the train
        local acc = defines.riding.acceleration.reversing
        for _, loco in ipairs(train.locomotives.front_movers) do
          if loco.unit_number == train_config.builder_loco.unit_number then
            acc = defines.riding.acceleration.accelerating
            break
          end
        end
        -- hit the gas up to the speed limit
        local speed = math.abs(train.speed)
        if speed < 0.04 then
          train_config.driver.riding_state = {
            acceleration = acc,
            direction = defines.riding.direction.straight,
          }
        elseif speed >= 0.04 then
          train_config.driver.riding_state = {
            acceleration = defines.riding.acceleration.nothing,
            direction = defines.riding.direction.straight,
          }
        elseif speed >= 0.06 then 
          train_config.driver.riding_state = {
            acceleration = defines.riding.acceleration.braking,
            direction = defines.riding.direction.straight,
          }
        end
        -- try to place the next wagon in the train
        local wagon = try_place_wagon[train_config[train_config.cursor].type](train_config, train_config[train_config.cursor])
        if wagon and wagon.valid then
          -- wagon landed, make sure things look good
          train_config.expected_length = train_config.expected_length + 1
          local carriage_config = train_config[train_config.cursor]
          carriage_config.built_wagon = wagon
          local input_inventory = train_config.input_chest.get_inventory(defines.inventory.chest)
          -- remove the wagon from the input chest
          local count = input_inventory.remove({
            name = carriage_config.item_to_place,
            count = 1,
          })
          if count ~= 1 then
            -- didn't have one in the inventory
            wagon.destroy()
            abort = true
            train_config.builder_loco.surface.create_entity({
              name = "flying-text",
              text = {"train-scaling.error-wagon-ingredient-missing"},
              position = train_config.builder_loco.position,
              color = {r = 1, g = 0.45, b = 0, a = 0.8},
              force = train_config.builder_loco.force,
            })
            abort_build(train_config)
          else
            -- fuel
            if carriage_config.fuel then
              local fuel_inventory = wagon.get_inventory(defines.inventory.fuel)
              if fuel_inventory and fuel_inventory.valid and fuel_inventory.can_insert(carriage_config.fuel) then
                local count = input_inventory.remove({
                  name = carriage_config.fuel,
                  count = game.item_prototypes[carriage_config.fuel].stack_size * (carriage_config.fuel_stacks or 1),
                })
                if count > 0 then
                  fuel_inventory.insert({
                    name = carriage_config.fuel,
                    count = count,
                  })
                else
                  abort = true
                  train_config.builder_loco.surface.create_entity({
                    name = "flying-text",
                    text = {"train-scaling.error-fuel-missing"},
                    position = train_config.builder_loco.position,
                    color = {r = 1, g = 0.45, b = 0, a = 0.8},
                    force = train_config.builder_loco.force,
                  })
                  abort_build(train_config)
                end
              end
            end

            -- grid
            if carriage_config.grid and not abort then
              if wagon.grid and wagon.grid.valid then
                for _, equipment_table in ipairs(carriage_config.grid) do
                  local removed = input_inventory.remove({
                    name = equipment_table.item_name,
                    count = 1,
                  })
                  if removed > 0 then
                    if not wagon.grid.put({
                      name = equipment_table.name,
                      position = equipment_table.position,
                    }) then
                      abort = true
                      train_config.builder_loco.surface.create_entity({
                        name = "flying-text",
                        text = {"train-scaling.error-equipment-placement-failure"},
                        position = train_config.builder_loco.position,
                        color = {r = 1, g = 0.45, b = 0, a = 0.8},
                        force = train_config.builder_loco.force,
                      })
                      abort_build(train_config)
                      break
                    end
                  else
                    abort = true
                    train_config.builder_loco.surface.create_entity({
                      name = "flying-text",
                      text = {"train-scaling.error-equipment-missing"},
                      position = train_config.builder_loco.position,
                      color = {r = 1, g = 0.45, b = 0, a = 0.8},
                      force = train_config.builder_loco.force,
                    })
                    abort_build(train_config)
                  end
                end
              else
                abort = true
                train_config.builder_loco.surface.create_entity({
                  name = "flying-text",
                  text = {"train-scaling.error-equipment-placement-failure"},
                  position = train_config.builder_loco.position,
                  color = {r = 1, g = 0.45, b = 0, a = 0.8},
                  force = train_config.builder_loco.force,
                })
                abort_build(train_config)
              end
            end

            if not abort then
              -- nothing else to fail, mark the carriage as complete
              -- update progress watermark for timeout checks
              train_config.progress_tick = event.tick
              -- notify other mods which might need to track when their train cars get built
              script.raise_event(defines.events.script_raised_built, {created_entity = wagon})
              -- move to the next car
              train_config.cursor = train_config.cursor - 1
              if train_config.cursor == 0 then
                -- done with the whole train
                local count = 0
                local template = train_config.template
                local template_train = template.train
                
                -- clear the build queue
                global.scaling_build_queue[i] = nil

                -- unregister if none running
                if not next(global.scaling_build_queue) then
                  script.on_nth_tick(5, nil)
                end

                train_config.driver.destroy()
                -- save burner state for next time
                local burner = train_config.builder_loco.burner
                global.scaling_burner_state[train_config.builder_station.unit_number] = {
                  currently_burning = burner.currently_burning,
                  remaining_burning_fuel = burner.remaining_burning_fuel,
                  inventory_contents = burner.inventory.get_contents(),
                }
                train_config.builder_loco.destroy()

                -- copy over the schedule
                local schedule = util.table.deepcopy(train_config.template.train.schedule)
                if schedule then
                  -- but start it at the top
                  schedule.current = 1
                  wagon.train.schedule = schedule
                end

                -- verify that the train now looks equal
                if not train_config.template or not train_config.template.valid or not train_eq(train_config.template.train, wagon.train) then
                  abort = true
                  train_config.builder_station.surface.create_entity({
                    name = "flying-text",
                    text = {"train-scaling.error-train-wrong-configuration"},
                    position = train_config.builder_station.position,
                    color = {r = 1, g = 0.45, b = 0, a = 0.8},
                    force = train_config.builder_station.force,
                  })
                  abort_build(train_config)
                end
                if not abort then
                  -- and, auto mode, off you go
                  wagon.train.manual_mode = false

                  local station_config = global.enabled_stations[template.surface.index][template.force.name][train_config.enabled_station_name]
                  if station_config then
                    -- station still exists, update it
                    -- decrement running build count
                    local station_entity_id, station_entity = next(station_config.entities)
                    if station_config.running_builds and station_config.running_builds > 0 then
                      station_config.running_builds = station_config.running_builds - 1
                    else
                      station_config.running_builds = 0
                    end

                    -- update metrics
                    global.scaling_station_metrics[i].built_trains = global.scaling_station_metrics[i].built_trains + 1
                    if not station_config.built_trains then
                      station_config.built_trains = 1
                    else
                      station_config.built_trains = station_config.built_trains + 1
                    end

                    -- count up current
                    for _, train in pairs(station_entity.get_train_stop_trains()) do
                      if train.id == template_train.id or train_eq(train, template_train) then
                        count = count + 1
                      end
                    end
                    -- store current count
                    station_config.current = count
                    -- if we had a target and we've reached it, remove the target
                    if station_config.target == count then
                      station_config.target = nil
                    end
                  end
                end
              end
            end
          end
        end
      end
    elseif train_config.type == "deconstruction" then
      local output_inv
      if not train_config.output_chest or not train_config.output_chest.valid then
        abort = true
        train_config.builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-output-chest-missing"},
          position = train_config.builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = train_config.builder_loco.force,
        })
      else
        output_inv = train_config.output_chest.get_inventory(defines.inventory.chest)
        if not output_inv or not output_inv.valid then
          abort = true
          train_config.builder_loco.surface.create_entity({
            name = "flying-text",
            text = {"train-scaling.error-output-chest-missing"},
            position = train_config.builder_loco.position,
            color = {r = 1, g = 0.45, b = 0, a = 0.8},
            force = train_config.builder_loco.force,
          })
        end
      end

      if abort then
        abort_deconstruct(train_config)
      else
        -- set the direction of stepping on the gas depending on which way the tug is "facing" on the train
        local acc = defines.riding.acceleration.reversing
        for _, loco in ipairs(train.locomotives.front_movers) do
          if loco.unit_number == train_config.builder_loco.unit_number then
            acc = defines.riding.acceleration.accelerating
            break
          end
        end
        -- hit the gas up to the speed limit
        local speed = math.abs(train.speed)
        if speed < 0.04 then
          train_config.driver.riding_state = {
            acceleration = acc,
            direction = defines.riding.direction.straight,
          }
        elseif speed >= 0.04 then
          train_config.driver.riding_state = {
            acceleration = defines.riding.acceleration.nothing,
            direction = defines.riding.direction.straight,
          }
        elseif speed >= 0.06 then 
          train_config.driver.riding_state = {
            acceleration = defines.riding.acceleration.braking,
            direction = defines.riding.direction.straight,
          }
        end
        -- get the carriage on the end of the train that isn't the tug
        local check = train_config.builder_loco.train.front_stock
        if check.unit_number == train_config.builder_loco.unit_number then
          check = train_config.builder_loco.train.back_stock
        end
        -- check if the carriage is close enough to deconstruct
        if total_position_diff(check, train_config.builder_station) < 5 then
          if deconstruct_carriage_into_inventory(check, output_inv) then
            train_config.expected_length = train_config.expected_length - 1
            train_config.progress_tick = game.tick
            if train_config.expected_length == 1 then
              train_config.driver.destroy()
              local burner = train_config.builder_loco.burner
              global.scaling_burner_state[train_config.builder_station.unit_number] = {
                currently_burning = burner.currently_burning,
                remaining_burning_fuel = burner.remaining_burning_fuel,
                inventory_contents = burner.inventory.get_contents(),
              }
              train_config.builder_loco.destroy()
              global.scaling_build_queue[i] = nil
              --metrics
              global.scaling_station_metrics[i].decommissioned_trains = global.scaling_station_metrics[i].decommissioned_trains + 1
            end
          else
            -- the deconstruction is failing due to not enough room in output; continue waiting in this state up to 5 minutes
            if game.tick - train_config.start_tick < 7200 then
              train_config.progress_tick = game.tick
            end
            train_config.driver.riding_state = {
              acceleration = defines.riding.acceleration.braking,
              direction = defines.riding.direction.straight,
            }
          end
        end
      end
    end
  end
end

local errors = {}
local function try_build(surface_id, force_id, station_name, station_config, scaling_config, count)
  if station_config.template and station_config.template.valid then
    -- clear error rate limiters for stations whose errors were long enough ago
    local tick = game.tick
    for i, error_tick in pairs(errors) do
      if tick - error_tick >= 180 then
        errors[i] = nil
      end
    end
    -- set up the build plan for the train desired
    local surface = game.surfaces[surface_id]
    local train = station_config.template.train
    local train_config = {}
    local train_items = {}
    local forward = {}
    for _, v in ipairs(train.locomotives.front_movers) do
      forward[v.unit_number] = true
    end
    -- generate train config table to build from template
    for i, carriage in ipairs(train.carriages) do
      if forward[carriage.unit_number] then
        train_config[i] = carriage_to_table[carriage.type](carriage, false)
      else
        train_config[i] = carriage_to_table[carriage.type](carriage, true)
      end
      local items_to_place = carriage.prototype.items_to_place_this
      if not train_items[carriage.name] then
        train_items[carriage.name] = items_to_place
      end
    end

    -- start scanning stations that might build for one that is ready to
    local fail_reasons = {}
    local built_count = 0
    for station_entity_id, station_entity in pairs(scaling_config.entities) do
      if not global.scaling_build_queue[station_entity.unit_number] then
        local build_config = util.table.deepcopy(train_config)
        local fail = false
        local fail_reason
        -- check inventory for parts
        -- get the input chest if there is one
        local x_chest, y_chest = rotate_relative_position[station_entity.direction](1.5, 0.5)
        local input_chest_entities = surface.find_entities_filtered({
          position = {
            x = station_entity.position.x + x_chest,
            y = station_entity.position.y + y_chest,
          },
          type = {
            "logistic-container",
            "container",
          },
          force = force_id,
        })
        if input_chest_entities == nil or input_chest_entities[1] == nil then
          fail = true
          fail_reason = "train-scaling.error-input-chest-missing"
        else
          -- check chest contents
          local chest_inventory = input_chest_entities[1].get_inventory(defines.inventory.chest)
          local contents = chest_inventory.get_contents()
          local item_counts = {}
          for i, carriage_config in ipairs(build_config) do
            local found = false
            -- iterate the items that might place the train entity we're after, see if we have one in the contents.
            for item_name in pairs(train_items[carriage_config.name]) do
              if contents[item_name] and contents[item_name] > 0 then
                -- found one, reduce its count by 1 and save which item we're planning to use for it.
                contents[item_name] = contents[item_name] - 1
                carriage_config.item_to_place = item_name
                found = true
                break
              end
            end
            if not found then
              fail = true
              fail_reason = "train-scaling.error-wagon-ingredient-missing"
            end
            -- if this carriage needs fuel, find that too
            if carriage_config.fuel_categories and not fail then
              local best
              for item_name, item_count in pairs(contents) do
                if game.item_prototypes[item_name].fuel_category and carriage_config.fuel_categories[game.item_prototypes[item_name].fuel_category] and item_count > 0 then
                  if not best or game.item_prototypes[item_name].fuel_value > game.item_prototypes[best].fuel_value then
                    best = item_name
                  end
                end
              end
              if best then
                local stacks = game.item_prototypes[carriage_config.item_to_place].place_result.get_inventory_size(defines.inventory.fuel)

                if scaling_config.fuel_stack_count then
                  stacks = scaling_config.fuel_stack_count
                end
                contents[best] = contents[best] - (game.item_prototypes[best].stack_size * stacks)
                carriage_config.fuel = best
                carriage_config.fuel_stacks = stacks
              end
              if not carriage_config.fuel then
                fail = true
                fail_reason = "train-scaling.error-fuel-missing"
              end
            end

            -- grid
            if carriage_config.grid and not fail then
              for _, grid in ipairs(carriage_config.grid) do
                if contents[grid.item_name] and contents[grid.item_name] >= 1 then
                  contents[grid.item_name] = contents[grid.item_name] - 1
                else
                  fail = true
                  fail_reason = "train-scaling.error-equipment-missing"
                  break
                end
              end
            end
          end

          if not fail then
            -- we seem to have the items, let's try dropping a builder train
            local x_train, y_train = rotate_relative_position[station_entity.direction](-2, 3)
            local direction = opposite[station_entity.direction]
            local train_position = {
              x = station_entity.position.x + x_train,
              y = station_entity.position.y + y_train,
            }
            local builder_loco = surface.create_entity({
              name = "locomotive",
              position = train_position,
              force = force_id,
              direction = direction,
            })
            if builder_loco and builder_loco.valid then
              -- builder is placed, check if it looks right
              if not in_cone[direction](builder_loco.orientation) then
                -- curved track does some wacky stuff, flip
                direction = opposite[direction]
                builder_loco.destroy()
                builder_loco = surface.create_entity({
                  name = "locomotive",
                  position = train_position,
                  force = force_id,
                  direction = direction,
                })
              end
              if not builder_loco or not builder_loco.valid then
                fail = true
                fail_reason = "train-scaling.error-construction-train-placement-fail"
              elseif not in_cone[opposite[station_entity.direction]](builder_loco.orientation)  then
                -- crossing track is getting the snap of the placement, give up
                builder_loco.destroy()
                fail = true
                fail_reason = "train-scaling.error-construction-train-placement-fail-crossing"
              end
              if builder_loco.valid and #builder_loco.train.carriages > 1 then
                -- we're connected to another train. this is a disaster, since we already set it into manual mode if it was in automatic.
                -- if it was in automatic mode moving into or out of the station, we should be able to get out of the way and get the other train back into auto mode.
                local front_stock = builder_loco.train.front_stock
                local back_stock = builder_loco.train.back_stock
                if builder_loco.disconnect_rolling_stock(defines.rail_direction.back) then
                  -- disconnecting the train behind us worked, no need to bail (yet).  Set the other train into auto mode if it's unoccupied,
                  if front_stock and front_stock.valid and not carriage_in_train(front_stock, builder_loco.train) then
                    if #front_stock.train.passengers == 0 then
                      front_stock.train.manual_mode = false
                    end
                  end
                  if back_stock and back_stock.valid and not carriage_in_train(back_stock, builder_loco.train) then
                    if #back_stock.train.passengers == 0 then
                      back_stock.train.manual_mode = false
                    end
                  end
                  -- set the speed to 0 to hopefully kill any extra momentum that other train gave us
                  builder_loco.train.speed = 0
                end
                if #builder_loco.train.carriages > 1 then
                  -- still connected to more than we're expecting, must be a train in front, possibly was just pulling in to this station
                  builder_loco.destroy()
                  if front_stock and front_stock.valid then
                    if #front_stock.train.passengers == 0 then
                      front_stock.train.manual_mode = false
                    end
                  end
                  if back_stock and back_stock.valid then
                    if #back_stock.train.passengers == 0 then
                      back_stock.train.manual_mode = false
                    end
                  end
                  fail = true
                  fail_reason = "train-scaling.error-construction-train-placement-too-close"
                end
              end
              if not fail then
                -- restore the burner state from last time 
                local fuel_inventory = builder_loco.get_inventory(defines.inventory.fuel)
                local burner = builder_loco.burner
                if global.scaling_burner_state[station_entity.unit_number] then
                  burner.currently_burning = global.scaling_burner_state[station_entity.unit_number].currently_burning
                  burner.remaining_burning_fuel = global.scaling_burner_state[station_entity.unit_number].remaining_burning_fuel
                  for name, count in pairs(global.scaling_burner_state[station_entity.unit_number].inventory_contents) do
                    fuel_inventory.insert({
                      name = name,
                      count = count,
                    })
                  end
                end
                -- re-fetch the inventory contents, the tug gets fuel priority
                contents = chest_inventory.get_contents()
                -- fill it with fuel!
                for item_name in pairs(contents) do
                  if contents[item_name] > 0 and game.item_prototypes[item_name].fuel_category and builder_loco.burner.fuel_categories[game.item_prototypes[item_name].fuel_category] then
                    local i = 1
                    while fuel_inventory.can_insert(item_name) and i <= 5 do
                      local removed = chest_inventory.remove({
                        name = item_name,
                        count = game.item_prototypes[item_name].stack_size,
                      })
                      if removed > 0 then
                        fuel_inventory.insert({
                          name = item_name,
                          count = removed,
                        })
                      end
                      i = i + 1
                    end
                  end
                end

                builder_loco.backer_name = "Train Scaling Train"
                builder_loco.color = {r = 1, g = 0.45, b = 0, a = 0.8}

                -- create the tug's non-player driver
                local driver = surface.create_entity({
                  name = "train-scaling-driver",
                  position = train_position,
                  force = force_id,
                })
                builder_loco.set_driver(driver)

                -- lots of reference material for the building queue handler
                build_config.driver = driver
                build_config.position = train_position
                build_config.direction = opposite[direction]
                build_config.cursor = #station_config.template.train.carriages
                build_config.builder_loco = builder_loco
                build_config.builder_station = station_entity
                build_config.builder_station_unit_number = station_entity.unit_number
                build_config.progress_tick = game.tick
                build_config.start_tick = game.tick
                build_config.input_chest = input_chest_entities[1]
                build_config.template = station_config.template
                build_config.enabled_station_name = station_name
                build_config.expected_length = 1
                build_config.surface_index = surface_id
                build_config.force_name = force_id
                build_config.type = "construction"

                -- attach the on_tick handler
                if not next(global.scaling_build_queue) then
                  script.on_nth_tick(5, building_tick)
                end
                -- finally, add it to the queue
                global.scaling_build_queue[station_entity.unit_number] = build_config

                -- tracking the number of in-progress train builds for checking if more need triggered
                station_config.running_builds = (station_config.running_builds or 0) + 1

                surface.create_entity({
                  name = "flying-text",
                  text = {"train-scaling.build-started", station_name},
                  position = station_entity.position,
                  color = {r = 1, g = 0.45, b = 0, a = 0.8},
                  force = station_entity.force,
                })

                -- check if we've started construction of enough copies of the train
                built_count = built_count + 1
                if built_count >= count then
                  return
                end
              end
            else
              fail = true
              fail_reason = "train-scaling.error-construction-train-placement-fail"
            end
          end
        end
        fail_reasons[station_entity.unit_number] = fail_reason
      end
    end
    -- didn't get all of our builds completed, create some floating text entities
    for station_entity_id, station_entity in pairs(scaling_config.entities) do
      if fail_reasons[station_entity_id] then
        if not errors[station_entity_id] then
          surface.create_entity({
            name = "flying-text",
            text = {fail_reasons[station_entity_id]},
            position = station_entity.position,
            color = {r = 1, g = 0.45, b = 0, a = 0.8},
            force = station_entity.force,
          })
          errors[station_entity_id] = tick
        end
      end
    end
  end
end

local function on_train_changed_state(event)
  if event.train.station and event.train.station.name == "train-scaling-stop" then
    -- a train stopped at a special station, let's see if we should deconstruct it
    if event.train.station.backer_name == "__mt__" then
      return
    end
    if next(event.train.get_contents()) or next(event.train.get_fluid_contents()) then
      event.train.station.surface.create_entity({
        name = "flying-text",
        text = {"train-scaling.error-cargo-not-empty"},
        position = event.train.station.position,
        color = {r = 1, g = 0.45, b = 0, a = 0.8},
        force = event.train.station.force,
      })
      return
    end
    if #event.train.passengers > 0 then
      event.train.station.surface.create_entity({
        name = "flying-text",
        text = {"train-scaling.error-train-occupied"},
        position = event.train.station.position,
        color = {r = 1, g = 0.45, b = 0, a = 0.8},
        force = event.train.station.force,
      })
      return
    end

    local carriage_count = #event.train.carriages
    -- front or back are.. fluid. compare positions to find which end of the train is closer to the station :/
    local back = event.train.back_stock
    local front = event.train.front_stock
    local station_entity = event.train.station
    if total_position_diff(front, station_entity) > total_position_diff(back, station_entity) then
      -- the back wagon's looking closer than the front, so let's reverse our assumption on which carriage we'll replace
      back = event.train.front_stock
      front = event.train.back_stock
    end
    local surface = back.surface
    local x_output, y_output = rotate_relative_position[station_entity.direction](1.5, -0.5)
    local output_chest_entities = surface.find_entities_filtered({
      position = {
        x = station_entity.position.x + x_output,
        y = station_entity.position.y + y_output,
      },
      type = {
        "logistic-container",
        "container",
      },
      force = station_entity.force,
    })
    local output_chest = output_chest_entities[1]
    if not output_chest or not output_chest.valid then
      station_entity.surface.create_entity({
        name = "flying-text",
        text = {"train-scaling.error-output-chest-missing"},
        position = station_entity.position,
        color = {r = 1, g = 0.45, b = 0, a = 0.8},
        force = station_entity.force,
      })
      return
    end
    -- grab the info we'll need for the new entity before destroying the old
    local create = {
      name = "locomotive",
      position = back.position,
      force = back.force,
      direction = defines.direction.north,
    }
    local output_inv = output_chest.get_inventory(defines.inventory.chest)
    if not deconstruct_carriage_into_inventory(back, output_inv) then
      station_entity.surface.create_entity({
        name = "flying-text",
        text = {"train-scaling.error-output-chest-full"},
        position = station_entity.position,
        color = {r = 1, g = 0.45, b = 0, a = 0.8},
        force = station_entity.force,
      })
      return
    end

    if carriage_count == 1 then
      --already done, it was a 1-car train - just increment the metric and don't worry about all this mess with the tug
      global.scaling_station_metrics[station_entity.unit_number].decommissioned_trains = global.scaling_station_metrics[station_entity.unit_number].decommissioned_trains + 1
      return
    end
    local builder_loco = surface.create_entity(create)
    if builder_loco and builder_loco.valid then
      -- tug is down, let's make sure we're in good shape to queue deconstruction..
      if #builder_loco.train.carriages == 1 then
        builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-construction-train-placement-fail"},
          position = builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = builder_loco.force,
        })
        return
      end
      if #builder_loco.train.carriages ~= carriage_count then
        -- wrong train length, we unintentionally connected to something - disconnect
        builder_loco.disconnect_rolling_stock(defines.rail_direction.front)
        if not carriage_in_train(builder_loco, front.train) then
          builder_loco.connect_rolling_stock(defines.rail_direction.front)
          builder_loco.disconnect_rolling_stock(defines.rail_direction.back)
        end
        if not carriage_in_train(builder_loco, front.train) then
          builder_loco.surface.create_entity({
            name = "flying-text",
            text = {"train-scaling.error-construction-train-placement-fail"},
            position = builder_loco.position,
            color = {r = 1, g = 0.45, b = 0, a = 0.8},
            force = builder_loco.force,
          })
          return
        end
      end

      if not carriage_in_train(builder_loco, front.train) then
        builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-construction-train-placement-fail"},
          position = builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = builder_loco.force,
        })
        return
      end

      -- the back of the train might have been on a curve, so we really have no idea if the orientation we used was right; check
      local flip = true
      if front.train.back_stock.unit_number == builder_loco.unit_number then
        -- we're the back stock, verify that we're a front mover
        for _, loco in pairs(builder_loco.train.locomotives.front_movers) do
          if loco.unit_number == builder_loco.unit_number then
            -- good to go, no need to flip
            flip = false
            break
          end
        end
      elseif front.train.front_stock.unit_number == builder_loco.unit_number then
        -- we're the front stock, verify that we're a back mover
        for _, loco in pairs(builder_loco.train.locomotives.back_movers) do
          if loco.unit_number == builder_loco.unit_number then
            -- good to go, no need to flip
            flip = false
            break
          end
        end
      end
      if flip then
        builder_loco.destroy()
        create.direction = opposite[create.direction]
        builder_loco = surface.create_entity(create)
      end

      if not builder_loco or not builder_loco.valid then
        -- somehow failed on the second place, just error
        if #builder_loco.train.carriages == 1 then
          builder_loco.surface.create_entity({
            name = "flying-text",
            text = {"train-scaling.error-construction-train-placement-fail"},
            position = builder_loco.position,
            color = {r = 1, g = 0.45, b = 0, a = 0.8},
            force = builder_loco.force,
          })
          return
        end
      end

      if #builder_loco.train.carriages ~= carriage_count then
        -- (second pass for the second placement) 
        -- wrong train length, we unintentionally connected to something - disconnect
        builder_loco.disconnect_rolling_stock(defines.rail_direction.front)
        if not carriage_in_train(builder_loco, front.train) then
          builder_loco.connect_rolling_stock(defines.rail_direction.front)
          builder_loco.disconnect_rolling_stock(defines.rail_direction.back)
        end
        if not carriage_in_train(builder_loco, front.train) then
          builder_loco.surface.create_entity({
            name = "flying-text",
            text = {"train-scaling.error-construction-train-placement-fail"},
            position = builder_loco.position,
            color = {r = 1, g = 0.45, b = 0, a = 0.8},
            force = builder_loco.force,
          })
          return
        end
      end

      if #builder_loco.train.carriages ~= carriage_count then
        -- still the wrong number, something's wrong
        builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-construction-train-placement-fail"},
          position = builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = builder_loco.force,
        })
        builder_loco.destroy()
        front.train.manual_mode = false
        return
      end

      -- restore burner state
      local fuel_inventory = builder_loco.get_inventory(defines.inventory.fuel)
      local burner = builder_loco.burner
      if global.scaling_burner_state[station_entity.unit_number] then
        burner.currently_burning = global.scaling_burner_state[station_entity.unit_number].currently_burning
        burner.remaining_burning_fuel = global.scaling_burner_state[station_entity.unit_number].remaining_burning_fuel
        for name, count in pairs(global.scaling_burner_state[station_entity.unit_number].inventory_contents) do
          fuel_inventory.insert({
            name = name,
            count = count,
          })
        end
      end
      local x_chest, y_chest = rotate_relative_position[station_entity.direction](1.5, 0.5)
      local input_chest_entities = surface.find_entities_filtered({
        position = {
          x = station_entity.position.x + x_chest,
          y = station_entity.position.y + y_chest,
        },
        type = {
          "logistic-container",
          "container",
        },
        force = station_entity.force,
      })
      if input_chest_entities and input_chest_entities[1] then
        -- fill it with fuel
        local chest_inventory = input_chest_entities[1].get_inventory(defines.inventory.chest)
        local contents = chest_inventory.get_contents()
        for item_name in pairs(contents) do
          if game.item_prototypes[item_name].fuel_category and builder_loco.burner.fuel_categories[game.item_prototypes[item_name].fuel_category] then
            local i = 1
            while fuel_inventory.can_insert(item_name) and i <= 5 do
              fuel_inventory.insert({
                name = item_name,
                count = chest_inventory.remove({
                  name = item_name,
                  count = game.item_prototypes[item_name].stack_size,
                }),
              })
              i = i + 1
            end
          end
        end
      end

      if builder_loco.burner.remaining_burning_fuel == 0 and not next(builder_loco.burner.inventory.get_contents()) then
        -- no fuel at all after restoring burner state and checking the input chest (if there was one), bail
        builder_loco.surface.create_entity({
          name = "flying-text",
          text = {"train-scaling.error-fuel-missing"},
          position = builder_loco.position,
          color = {r = 1, g = 0.45, b = 0, a = 0.8},
          force = builder_loco.force,
        })
        builder_loco.destroy()
        return
      end
      builder_loco.backer_name = "Train Scaling Train"
      builder_loco.color = {r = 1, g = 0.45, b = 0, a = 0.8}

      -- create the tug's non-player driver
      local driver = surface.create_entity({
        name = "train-scaling-driver",
        position = builder_loco.position,
        force = builder_loco.force,
      })
      builder_loco.set_driver(driver)

      -- set up the entry in the queue
      local build_config = {
        type = "deconstruction",
        builder_station = station_entity,
        builder_station_unit_number = station_entity.unit_number,
        builder_loco = builder_loco,
        driver = driver,
        expected_length = carriage_count,
        progress_tick = game.tick,
        start_tick = game.tick,
        output_chest = output_chest,
      }

      -- attach the on_tick handler
      if not next(global.scaling_build_queue) then
        script.on_nth_tick(5, building_tick)
      end
      -- finally, add it to the queue
      global.scaling_build_queue[station_entity.unit_number] = build_config

    else
      -- couldn't make the tug
      station_entity.surface.create_entity({
        name = "flying-text",
        text = {"train-scaling.error-construction-train-placement-fail"},
        position = station_entity.position,
        color = {r = 1, g = 0.45, b = 0, a = 0.8},
        force = station_entity.force,
      })
    end
  end
end
script.on_event(defines.events.on_train_changed_state, on_train_changed_state)

local function try_decommission(surface_id, force_id, station_name, station_config, count)
  local decommed_count = 0
  local station_entity_id, station_entity = next(station_config.entities)
  for _, train in ipairs(station_entity.get_train_stop_trains()) do
    if not next(train.get_contents()) and not next(train.get_fluid_contents()) and not train.manual_mode then
      if train.id ~= station_config.template.train.id or station_config.current == 1 then
        local schedule = util.table.deepcopy(train.schedule)

        local insert_index
        local skip = false
        for schedule_index, record in ipairs(schedule.records) do
          if #record.wait_conditions == 1 and record.wait_conditions[1].type == "empty" then
            insert_index = schedule_index + 1
          end
          if record.station == station_config.construction_station then
            -- already in the schedule, skip
            skip = true
          end
        end
        if not skip then
          if insert_index then
            -- we found a station that's set to just empty, insert the scaling station afterward
            table.insert(schedule.records, insert_index, {
              station = station_config.construction_station,
              wait_conditions = {
                { 
                  type = "inactivity",
                  compare_type = "or",
                  ticks = 600,
                },
              },
            })
          else
            -- didn't find a station (and it's empty now so we don't want to risk it getting cargo added), just overwrite the schedule wholesaie
            if train.station and train.station.valid then
              -- if this train is stopped at a station keep that station in the schedule
              schedule.records = {
                {
                  station = train.station.backer_name,
                  wait_conditions = {
                    { 
                      type = "time",
                      compare_type = "or",
                      ticks = 60,
                    },
                  },
                },
                {
                  station = station_config.construction_station,
                  wait_conditions = {
                    { 
                      type = "inactivity",
                      compare_type = "or",
                      ticks = 600,
                    },
                  },
                },
              }
            else
              -- fresh schedule
              schedule.records = {
                {
                  station = station_config.construction_station,
                  wait_conditions = {
                    { 
                      type = "inactivity",
                      compare_type = "or",
                      ticks = 600,
                    },
                  },
                },
              }
            end
            schedule.current = 1
          end
          -- write the schedule
          train.schedule = schedule
          -- increment success count
          decommed_count = decommed_count + 1
          if decommed_count >= count then
            break
          end
        end
      end
    end
  end
  if decommed_count > 0 then
    -- increment metric
    if not station_config.decommissioned_trains then
      station_config.decommissioned_trains = decommed_count
    else
      station_config.decommissioned_trains = station_config.decommissioned_trains + decommed_count
    end

    -- update the count
    local template_train = station_config.template.train
    local match_count = 0
    -- count up current
    for _, train in pairs(station_entity.get_train_stop_trains()) do
      if train.id == template_train.id or train_eq(train, template_train) then
        match_count = match_count + 1
      end
    end
    local old_count = station_config.current
    -- store current count
    station_config.current = match_count
    if match_count == 0 or old_count == 1 then
      station_config.template = nil
    end
    -- if we had a target and we've reached it, remove the target
    if station_config.target == match_count then
      station_config.target = nil
    end
  end
end

-- cursors for the tick handler that runs all the time - limit the scan to checking a set # of stations per run,
-- so that performance won't get bad on maps with boatloads of stations
local cursor_surface
local cursor_force
local cursor_station
local cursor_entity
local function construction_check(event)
  local check_count = 0
  -- check that the cursor surface hasn't been nilled between ticks
  if cursor_surface and not rawget(global.enabled_stations, cursor_surface) then
    cursor_surface = nil
  end
  -- scan surfaces
  for surface, forces in next, global.enabled_stations, cursor_surface do
    -- skip __mt__ entries
    if type(forces) ~= "string" then
      -- check that the force hasn't been nilled between ticks
      if cursor_force and not rawget(forces, cursor_force) then
        cursor_force = nil
      end
      -- scan stations
      for force, stations in next, forces, cursor_force do
        -- skip __mt__ entries
        if type(stations) ~= "string" then
          -- check that the station name hasn't been deconfigured between ticks
          if cursor_station and not rawget(stations, cursor_station) then
            cursor_station = nil
          end
          -- scan stations
          for station_name, station_config in next, stations, cursor_station do
            if station_config.template and station_config.construction_station then
              -- config is ready for this stations, check if we have scaling orders through config or signals
              if station_config.target then
                -- configured to scale, try to reach target
                if station_config.target > station_config.current + (station_config.running_builds or 0) then
                  try_build(surface, force, station_name, station_config, global.scaling_stations[surface][force][station_config.construction_station], station_config.target - (station_config.current + (station_config.running_builds or 0)))
                elseif station_config.target < station_config.current then
                  try_decommission(surface, force, station_name, station_config, station_config.current - station_config.target)
                end
                -- count that as 5 stations worth of signal work; it's probably more.
                check_count = check_count + 5
              else
                -- check that the cursor entity hasn't been deconfigured between ticks
                if cursor_entity and not station_config.entities[cursor_entity] then
                  cursor_entity = nil
                end
                -- scan entities for signals
                for entity_unit_number, entity in next, station_config.entities, cursor_entity do
                  if entity.valid then
                    local up
                    local down
                    local signals = entity.get_merged_signals()
                    if signals then
                      -- some signals present, check them.
                      for _, signal_table in ipairs(signals) do
                        if signal_table.signal.name == "signal-train-scale-up" and signal_table.count > 0 then
                          up = signal_table.count
                        elseif signal_table.signal.name == "signal-train-scale-down" and signal_table.count > 0 then
                          down = signal_table.count
                        end
                      end
                      -- if one signal (and not the other) is present, check if we're outside the rate limit for this action on this entity and if so, trigger
                      if up and game.tick - (up * 60) > global.scaling_signal_holdoff_timestamps[entity.unit_number].up and not down then
                        global.scaling_signal_holdoff_timestamps[entity.unit_number].up = game.tick
                        try_build(surface, force, station_name, station_config, global.scaling_stations[surface][force][station_config.construction_station], 1)
                      elseif down and game.tick - (down * 60) > global.scaling_signal_holdoff_timestamps[entity.unit_number].down and station_config.current > 1 and not up then
                        global.scaling_signal_holdoff_timestamps[entity.unit_number].down = game.tick
                        try_decommission(surface, force, station_name, station_config, 1)
                      end
                    end
                  end
                  cursor_entity = entity_unit_number

                  check_count = check_count + 1
                  if check_count >= 15 then
                    return
                  end
                end
                cursor_entity = nil
              end
            end

            cursor_station = station_name
            if check_count >= 15 then
              return
            end
          end
          cursor_station = nil
        end
        cursor_force = force
      end
      cursor_force = nil
    end
    cursor_surface = surface
  end
  cursor_surface = nil
end
script.on_nth_tick(300, construction_check)

-- UI stuff!
local open_entity = {}
local open_train_dropdown_mapping = {}
local function get_trains_dropdown(entity, player)
  local template = global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].template
  local template_train_id
  if template and template.valid then
    template_train_id = template.train.id
  end
  local items = {{"train-scaling.config-no-template"}}
  open_train_dropdown_mapping[player.index] = {0}
  local selected = 1
  for i, train in ipairs(entity.get_train_stop_trains()) do
    if train.id == template_train_id then
      selected = i + 1
    end
    local loco
    local forward = 0
    for _, entity in ipairs(train.locomotives.front_movers) do
      if not loco then
        loco = entity
      end
      forward = forward + 1
    end
    local backward = 0
    for _, entity in ipairs(train.locomotives.back_movers) do
      if not loco then
        loco = entity
      end
      backward = backward + 1
    end
    local cargo = 0
    local fluid = 0
    local artillery = 0
    for _, carriage in ipairs(train.carriages) do
      if carriage.type == "cargo-wagon" then
        cargo = cargo + 1
      elseif carriage.type == "fluid-wagon" then
        fluid = fluid + 1
      elseif carriage.type == "artillery-wagon" then
        artillery = artillery + 1
      end
    end
    -- todo, change these to the fancy new item strings in 0.17 - https://www.factorio.com/blog/post/fff-237
    -- [icon=item/locomotive] etc
    if loco then
      local train_string = string.format("%dL", forward)
      if cargo > 0 then
        train_string = string.format("%s %dC", train_string, cargo)
      end
      if fluid > 0 then
        train_string = string.format("%s %dF", train_string, fluid)
      end
      if artillery > 0 then
        train_string = string.format("%s %dA", train_string, artillery)
      end
      if backward > 0 then
        train_string = string.format("%s %dL", train_string, backward)
      end
      table.insert(items, string.format("%s, %dst", train_string, #train.schedule.records))
      table.insert(open_train_dropdown_mapping[player.index], loco)
    end
  end
  if template and template.valid and selected == 1 then
    -- there's a template out there but it's not one of the trains we scanned
    table.insert(items, {"train-scaling.disassociated-train"})
    selected = #items
    -- add a buffer item for the redraw
    table.insert(open_train_dropdown_mapping[player.index], false)
  end
  return items, selected
end

local function draw_normal_station_gui(player)
  local entity = open_entity[player.index]

  local empty = true
  for k, v in pairs(global.scaling_stations[entity.surface.index][entity.force.name]) do
    if k ~= "__mt__" then
      empty = false
      break
    end
  end
  if empty then
    -- no stations built, bail
    return
  end

  if player.gui.left.train_scaling_config then
    player.gui.left.train_scaling_config.destroy()
  end
  local frame = player.gui.left.add({
    name = "train_scaling_config",
    type = "frame",
    direction = "vertical",
  })
  local config_flow = frame.add({
    name = "train_scaling_config_flow",
    type = "flow",
    direction = "vertical",
  })
  local enabled = (global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] ~= nil)
  local mode_checkbox = config_flow.add({
    name = "train_scaling_config_enable_toggle",
    type = "checkbox",
    state = enabled,
    caption = {"train-scaling.config-enable-scaling"},
    tooltip = {"train-scaling.config-enable-scaling-tooltip"},
  })
  if enabled then
    local items, selected = get_trains_dropdown(entity, player)
    local template_flow = config_flow.add({
        name = "train_scaling_template_flow",
        type = "flow",
        direction = "horizontal",
        caption = {"train-scaling.config-template-label"},
    })
    local dropdown = template_flow.add({
      name = "train_scaling_config_template_dropdown",
      type = "drop-down",
      items = items,
      selected_index = selected,
      tooltip = {"train-scaling.config-template-tooltip"}
    })
    local goto_button = template_flow.add({
      name = "train_scaling_config_template_goto_button",
      type = "button",
      enabled = selected ~= 1,
      caption = {"train-scaling.config-goto-label"},
      tooltip = {"train-scaling.config-goto-tooltip"},
    })

    if selected ~= 1 then
      local station_config = global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name]
      local count = 0
      local template_train = station_config.template.train
      for _, train in pairs(entity.get_train_stop_trains()) do
        if train.id == template_train.id or train_eq(train, template_train) then
          count = count + 1
        end
      end
      station_config.current = count
      local stations = {}
      local selected = 0
      for name, v in pairs(global.scaling_stations[entity.surface.index][entity.force.name]) do
        if type(v) ~= "string" then
          table.insert(stations, name)
          if station_config.construction_station == name then
            selected = #stations
          end
        end
      end
      if selected == 0 then
        table.insert(stations, "")
        selected = #stations
      end

      local station_picker = config_flow.add({
        name = "train_scaling_station_picker_dropdown",
        type = "drop-down",
        items = stations,
        selected_index = selected,
        tooltip = {"train-scaling.config-scaling-picker-tooltip"},
      })

      local slider_flow = config_flow.add({
        name = "train_scaling_config_slider_flow",
        type = "flow",
        direction = "horizontal",
      })
      local slider = slider_flow.add({
        name = "train_scaling_config_target_slider",
        type = "slider",
        minimum_value = 0,
        maximum_value = 25,
        value = station_config.target or count,
        tooltip = {"train-scaling.config-target-count-tooltip"},
      })
      local slider_text = slider_flow.add({
        name = "train_scaling_config_target_textbox",
        type = "textfield",
        text = station_config.target or count,
        tooltip = {"train-scaling.config-target-count-tooltip"},
      })
      local count_label = config_flow.add({
        name = "train_scaling_config_count_display",
        type = "label",
        caption = {"train-scaling.config-current-count", count},
      })
      if station_config.running_builds and station_config.running_builds > 0 then
        count_label.caption = {"train-scaling.config-current-count-with-building", count, station_config.running_builds}
      end
      local build_count_display = config_flow.add({
        name = "train_scaling_config_build_count",
        type = "label",
        caption = {"train-scaling.config-build-count", station_config.built_trains or 0 },
      })
      local decommissioned_count_display = config_flow.add({
        name = "train_scaling_config_decom_count",
        type = "label",
        caption = {"train-scaling.config-decommissioned-count", station_config.decommissioned_trains or 0 },
      })
    end
  end
end

local function update_normal_station_gui(player)
  local entity = open_entity[player.index]

  if not player.gui.left.train_scaling_config or not entity or not entity.valid then
    return
  end
  local station_config = global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name]
  local config_flow = player.gui.left.train_scaling_config.train_scaling_config_flow
  local mode_checkbox = config_flow.train_scaling_config_enable_toggle
  if station_config and mode_checkbox.state == false then
    -- found config but checkbox thinks we're disabled, 
    return draw_normal_station_gui(player)
  elseif not station_config and mode_checkbox.state == true then
    -- no config but checkbox thinks we're enabled, redraw
    return draw_normal_station_gui(player)
  end
  -- if we're not configured, already done with updates
  if not station_config then
    return
  end
  
  local template_flow = config_flow.train_scaling_template_flow
  if not template_flow then
    return
  end
  local template_dropdown = config_flow.train_scaling_template_flow.train_scaling_config_template_dropdown
  if station_config.template and station_config.template.valid then
    if template_dropdown.selected_index == 1 then
      -- template configured but gui thinks it isn't, redraw
      return draw_normal_station_gui(player)
    elseif open_train_dropdown_mapping[player.index][template_dropdown.selected_index] then
      if station_config.template.unit_number ~= open_train_dropdown_mapping[player.index][template_dropdown.selected_index].unit_number then
        --template doesn't match what we have in the dropdown, redraw
        return draw_normal_station_gui(player)
      end
    end
  else
    if template_dropdown.selected_index ~= 1 then
      -- template not configured but gui thinks it is, redraw
      return draw_normal_station_gui(player)
    end
    -- no template is selected so we're done with updates
    return
  end

  local slider_flow = config_flow.train_scaling_config_slider_flow
  if slider_flow then
    if slider_flow.train_scaling_config_target_slider.slider_value ~= station_config.target and station_config.target then
      slider_flow.train_scaling_config_target_slider.slider_value = station_config.target
      slider_flow.train_scaling_config_target_textbox.text = station_config.target
    end
  end

  local count_label = config_flow.train_scaling_config_count_display
  if count_label then
        if station_config.running_builds and station_config.running_builds > 0 then
      count_label.caption = {"train-scaling.config-current-count-with-building", station_config.current, station_config.running_builds}
    else
      count_label.caption = {"train-scaling.config-current-count", station_config.current}
    end
  end

  local build_count_display = config_flow.train_scaling_config_build_count
  if build_count_display then
    build_count_display.caption = {"train-scaling.config-build-count", station_config.built_trains or 0 }
  end

  local decommissioned_count_display = config_flow.train_scaling_config_decom_count
  if decommissioned_count_display then
    decommissioned_count_display.caption = {"train-scaling.config-decommissioned-count", station_config.decommissioned_trains or 0 }
  end
end

local function draw_scaling_station_gui(player)
  local entity = open_entity[player.index]
  if player.gui.left.train_scaling_config then
    player.gui.left.train_scaling_config.destroy()
  end
  local scaling_config = global.scaling_stations[entity.surface.index][entity.force.name][entity.backer_name]
  local frame = player.gui.left.add({
    name = "train_scaling_config",
    type = "frame",
    direction = "vertical",
  })
  local config_flow = frame.add({
    name = "train_scaling_config_flow",
    type = "flow",
    direction = "vertical",
  })
  local stack_index = 1
  if scaling_config.fuel_stack_count then
    stack_index = scaling_config.fuel_stack_count + 1
  end
  local fuel_stack_dropdown = config_flow.add({
    name = "train_scaling_station_fuel_stack_dropdown",
    type = "drop-down",
    tooltip = {"train-scaling.config-scaling-fuel-tooltip"},
    items = {
      {"train-scaling.config-fuel-fill"},
      {"train-scaling.config-fuel-1stack"},
      {"train-scaling.config-fuel-2stack"},
      {"train-scaling.config-fuel-3stack"},
    },
    selected_index = stack_index,
  })
  local build_count_display = config_flow.add({
    name = "train_scaling_config_build_count",
    type = "label",
    caption = {"train-scaling.config-build-count", global.scaling_station_metrics[entity.unit_number].built_trains },
  })
  local decommissioned_count_display = config_flow.add({
    name = "train_scaling_config_decom_count",
    type = "label",
    caption = {"train-scaling.config-decommissioned-count", global.scaling_station_metrics[entity.unit_number].decommissioned_trains },
  })
end

local function update_scaling_station_gui(player)
  local entity = open_entity[player.index]
  if not player.gui.left.train_scaling_config or not entity then
    return
  end
  local scaling_config = global.scaling_stations[entity.surface.index][entity.force.name][entity.backer_name]
  local config_flow = player.gui.left.train_scaling_config.train_scaling_config_flow

  local stack_index = 1
  if scaling_config.fuel_stack_count then
    stack_index = scaling_config.fuel_stack_count + 1
  end
  local fuel_stack_dropdown = config_flow.train_scaling_station_fuel_stack_dropdown
  if stack_index ~= fuel_stack_dropdown.selected_index then
    fuel_stack_dropdown.selected_index = stack_index
  end

  local build_count_display = config_flow.train_scaling_config_build_count
  if build_count_display then
    build_count_display.caption = {"train-scaling.config-build-count", global.scaling_station_metrics[entity.unit_number].built_trains }
  end

  local decommissioned_count_display = config_flow.train_scaling_config_decom_count
  if decommissioned_count_display then
    decommissioned_count_display.caption = {"train-scaling.config-decommissioned-count", global.scaling_station_metrics[entity.unit_number].decommissioned_trains }
  end
end

local function gui_refresh(event)
  for player_index, entity in pairs(open_entity) do
    if entity and entity.valid then
      if entity.name == "train-scaling-stop" then
        update_scaling_station_gui(game.players[player_index])
      else
        update_normal_station_gui(game.players[player_index])
      end
    end
  end
end

local function on_gui_opened(event)
  if event.entity and event.entity.type == "train-stop" then
    local player = game.players[event.player_index]
    if player.permission_group.allows_action(defines.input_action.edit_train_schedule) then
      if event.entity.name == "train-scaling-stop" then
        if not next(open_entity) then
          script.on_nth_tick(60, gui_refresh)
        end
        open_entity[event.player_index] = event.entity
        draw_scaling_station_gui(player)
      else
        if not next(open_entity) then
          script.on_nth_tick(60, gui_refresh)
        end
        open_entity[event.player_index] = event.entity
        draw_normal_station_gui(player)
      end
    end
  end
end
script.on_event(defines.events.on_gui_opened, on_gui_opened)

local function on_gui_closed(event)
  if event.entity and event.entity.type == "train-stop" then
    open_entity[event.player_index] = nil
    local player = game.players[event.player_index]
    if player.gui.left.train_scaling_config then
      player.gui.left.train_scaling_config.destroy()
    end
    if not next(open_entity) then
      script.on_nth_tick(60, nil)
    end
  end
end
script.on_event(defines.events.on_gui_closed, on_gui_closed)

local gui_change_handlers = {
  train_scaling_config_enable_toggle = function(event)
    local entity = open_entity[event.player_index]
    if event.element.state == true then
      if entity.backer_name == "__mt__" then
        -- blacklist this station name since it'll overwrite our metatable markers
        draw_normal_station_gui(game.players[event.player_index])
        return
      end
      global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] = {
        construction_station = "Train Scaling Station",
        entities = {},
      }
      local entities = global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].entities
      for _, station in ipairs(entity.surface.find_entities_filtered({type = "train-stop", force = entity.force})) do
        if station.backer_name == entity.backer_name then
          entities[station.unit_number] = station
        end
      end
    else
      global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name] = nil
    end
    entity.last_user = game.players[event.player_index]
    draw_normal_station_gui(game.players[event.player_index])
  end,

  train_scaling_config_target_slider = function(event)
    local entity = open_entity[event.player_index]
    local station_config = global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name]
    event.element.slider_value = math.floor(event.element.slider_value)
    station_config.target = event.element.slider_value
    if station_config.target == station_config.current then
      station_config.target = nil
    end
    entity.last_user = game.players[event.player_index]
    event.element.parent.train_scaling_config_target_textbox.text = event.element.slider_value
  end,

  train_scaling_config_target_textbox = function(event)
    local entity = open_entity[event.player_index]
    local station_config = global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name]
    if tonumber(event.element.text) and tonumber(event.element.text) >= 0 then
      if tonumber(event.element.text) > 1000 then
        event.element.text = 1000
      end
      station_config.target = tonumber(event.element.text)
      if station_config.target == station_config.current then
        station_config.target = nil
      end
      event.element.parent.train_scaling_config_target_slider.slider_value = tonumber(event.element.text)
    elseif not tonumber(event.element.text) and string.len(event.element.text) > 0 then
      event.element.text = station_config.target or event.element.parent.train_scaling_config_target_slider.slider_value
    end
    entity.last_user = game.players[event.player_index]
  end,

  train_scaling_config_template_dropdown = function(event)
    local entity = open_entity[event.player_index]
    if event.element.selected_index == 1 then
      global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].template = nil
    else
      if open_train_dropdown_mapping[event.player_index] and open_train_dropdown_mapping[event.player_index][event.element.selected_index] and open_train_dropdown_mapping[event.player_index][event.element.selected_index].valid then
        global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].template = open_train_dropdown_mapping[event.player_index][event.element.selected_index]
      end
    end
    entity.last_user = game.players[event.player_index]
    draw_normal_station_gui(game.players[event.player_index])
  end,

  train_scaling_station_picker_dropdown = function(event)
    local entity = open_entity[event.player_index]
    if event.element.items[event.element.selected_index] ~= "" then
      global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].construction_station = event.element.items[event.element.selected_index]
    end
    entity.last_user = game.players[event.player_index]
  end,

  train_scaling_station_fuel_stack_dropdown = function(event)
    local entity = open_entity[event.player_index]
    local scaling_config = global.scaling_stations[entity.surface.index][entity.force.name][entity.backer_name]
    if event.element.selected_index == 1 then
      scaling_config.fuel_stack_count = nil
    else
      scaling_config.fuel_stack_count = event.element.selected_index - 1
    end
    entity.last_user = game.players[event.player_index]
  end,
}

local gui_click_handlers = {
  train_scaling_config_template_goto_button = function(event)
    local entity = open_entity[event.player_index]
    local template = global.enabled_stations[entity.surface.index][entity.force.name][entity.backer_name].template
    if template and template.valid then
      game.players[event.player_index].opened = template
    end
  end,
}

local function on_gui_event(event)
  if gui_change_handlers[event.element.name] then
    gui_change_handlers[event.element.name](event)
  end
end
script.on_event(defines.events.on_gui_checked_state_changed, on_gui_event)
script.on_event(defines.events.on_gui_selection_state_changed, on_gui_event)
script.on_event(defines.events.on_gui_text_changed, on_gui_event)
script.on_event(defines.events.on_gui_value_changed, on_gui_event)

local function on_click_event(event)
  if gui_click_handlers[event.element.name] then
    gui_click_handlers[event.element.name](event)
  end
end
script.on_event(defines.events.on_gui_click, on_click_event)

-- metatables for attaching to stuff in the global table - string ids for each metatable for reattachment between loads
local global_tree_metatables
global_tree_metatables = {
  scaling_surface = {
    __index = function(table, key)
      rawset(table, key, setmetatable({__mt__="scaling_force"}, global_tree_metatables.scaling_force))
      return rawget(table, key)
    end,
  },
  scaling_force = {
    __index = function(table, key)
      rawset(table, key, setmetatable({__mt__="scaling_name"}, global_tree_metatables.scaling_name))
      return rawget(table, key)
    end,
  },
  scaling_name = {
    __index = function(table, key)
      rawset(table, key, {entities={}})
      return rawget(table, key)
    end,
  },
  enabled_surface = {
    __index = function(table, key)
      rawset(table, key, setmetatable({__mt__="enabled_force"}, global_tree_metatables.enabled_force))
      return rawget(table, key)
    end,
  },
  enabled_force = {
    __index = function(table, key)
      rawset(table, key, {})
      return rawget(table, key)
    end,
  },
  metrics = {
    __index = function(table, key)
      rawset(table, key, 0)
      return 0
    end,
  },
  station_metrics = {
    __index = function(table, key)
      rawset(table, key, setmetatable({__mt__="metrics"}, global_tree_metatables.metrics))
      return rawget(table, key)
    end,
  },
  holdoff_timestamps = {
    __index = function(table, key)
      rawset(table, key, {
        up = 0,
        down = 0,
      })
      return rawget(table, key)
    end,
  },
}

-- on init, set up the global tables for the first time
local function on_init()
  global.scaling_stations = setmetatable({__mt__="scaling_surface"}, global_tree_metatables.scaling_surface)
  global.enabled_stations = setmetatable({__mt__="enabled_surface"}, global_tree_metatables.enabled_surface)
  global.scaling_station_metrics = setmetatable({__mt__="station_metrics"}, global_tree_metatables.station_metrics)
  global.scaling_signal_holdoff_timestamps = setmetatable({__mt__="holdoff_timestamps"}, global_tree_metatables.holdoff_timestamps)
  global.scaling_build_queue = {}
  global.scaling_burner_state = {}
end
script.on_init(on_init)

-- on load, reattach those metatables to the whole tree
local function recursive_attach(table)
  for k, v in pairs(table) do
    if k == "__mt__" then
      setmetatable(table, global_tree_metatables[v])
    elseif type(v) == "table" then
      recursive_attach(v)
    end
  end
end

local function on_load()
  recursive_attach(global.scaling_stations)
  recursive_attach(global.enabled_stations)
  recursive_attach(global.scaling_station_metrics)
  recursive_attach(global.scaling_signal_holdoff_timestamps)
  -- if something's in the build queue, reregister
  if next(global.scaling_build_queue) then
    script.on_nth_tick(5, building_tick)
  end
end
script.on_load(on_load)
