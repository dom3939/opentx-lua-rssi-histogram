-- Looking for configuration?  Search this file for CONFIG
--
-- RSSI Histogram and Simple Widget Implementation V1.0
--
-- The goal of this telemetry script is to provide a simple way to define
-- custom widgets, including graphs, for the Taranis X9D, QX& and close variants.
--
-- Disclaimer:
-- 
-- Although this script has been tested and OpenTX is designed to tolerate
-- LUA script bugs, it can not be guaranteed that this script is safe to use.
-- You assume all liability for any damage caused by the result of using
-- this script. Use this script at your own risk.


-- == Widget Definitions ==
--
-- Thi is your library of "widgets" that you can select from in your telemetry screen.
-- Of course, you can also create your own.
--
-- Using:
--
--   Refer to the Readme.md file for examples.
--
-- Creating:
--
--   Basic definition is
--  
--   widget = {
--     init = function(self) end;
--     bg = function(self) end;
--     draw = function(self, rx, ry, rw, rh) end;
--   }
--  
--   init: Called at start and if resetGlobalVarIndex GV is > 0
--   bg: Called priodically whether the telemetry screen is shown or not
--   draw: Called when the LCD is ready to be drawn to
--  
--   init, bg, and draw are all optional can can be omitted if they are
--   not needed.


-- RSSI graph widget
--
-- Draws a reatime RSSI histogram.  Autoscales Y axis.  Uses log scale for
-- amounts so that rare readings still show up.
--
-- Usage Example:
-- 
--  widgets = {
--    {
--      column = 2;
--      row = 0;
--      width = 2;
--      height = 4;
--      widget = RSSIHistogramWidget({greyscale = true})
--    }
--  }
--
-- Options:
--
--  greyscale: If true, then the RSSI critical is drawn as a greyscale
--    rectangle.  This won't work on the QX7, which has a monochrome
--    display
--
--
-- Need a width of at least 100 as-coded or it wont draw anything.
local function RSSIHistogramWidget(options)
  local widget = {
  init = function(self)
    self.max_bucket = 0
    self.max_log_bucket = 0
    for i=1, 100
    do
    self.buckets[i] = 0
    end
  end;

  bg = function(self)
      local rssi = getRSSI()
      if rssi <= 0 then
        return
      elseif rssi > 100 then
        -- sometimes RSSI can be > 100, but cap it here for graphing purposes
        rssi = 100
      end
    
      self.buckets[rssi] = self.buckets[rssi] + 1
    
      if self.buckets[rssi] > self.max_bucket then
        -- We have a new maximum.  Adjust y scaling.
        self.max_bucket = self.buckets[rssi]
        self.max_log_bucket = math.log(self.max_bucket)
      end
  end;

  draw = function(self, rx, ry, rw, rh)
    if rw < 100 then
      -- not enough space to draw
      return
    end
    
    -- center the graph
    rx = rx + (rw - 100) / 2
    
    -- bottom line is 4 pixels
    local by = ry + rh - 4
    local bh = by - ry
    
    -- draw the bottom axis
    lcd.drawLine(rx, by + 1, rx + 100, by + 1, SOLID, FORCE)
    
    -- draw pixel marks of varying lengths at each 5%, 10% and 50%
    for i=0, 100, 5 do
      local height = 2
      if i % 50 == 0 then
        height = 4
      elseif i % 10 == 0 then
        height = 3
      end
      lcd.drawLine(rx + i, by + 1, rx + i, by + 1 + height, SOLID, FORCE)
    end

    local rssi, _, alarm_crit = getRSSI()

    -- draw low and critical marks
    if options.greyscale then
      lcd.drawFilledRectangle(rx, ry, alarm_crit, by - ry + 1, GREY_DEFAULT)
    else
      lcd.drawLine(rx, by + 2, rx + alarm_crit, by + 2, SOLID, FORCE)
    end 

    -- draw each bucket
    for i = 1, 100 do
      local bval = self.buckets[i]
      if bval > 0 then
        local height = bh * math.log(bval) / self.max_log_bucket 
        local x = rx + i
        local y = by - height

        -- Draw the line differently if it's the current RSSI.  This gives
        -- a visual indicator of where RSSI currently is.
        if i == rssi then
          if options.greyscale then
            lcd.drawLine(x, y, x, by, SOLID, GREY_DEFAULT + FORCE)
          end
          lcd.drawPoint(x, y)
        else
          lcd.drawLine(x, y, x, by, SOLID, FORCE)
        end
      end
    end
  end,

  -- Local state maintained by this widget
  buckets = {},
  }

  return widget
end


-- LabelWidget
--
-- Draws a label that can be directly provided, or optionally provided via a
-- callback function.
--
-- Usage Example:
--
-- 
--  widgets = {
--  {
--    column = 0;
--    row = 0;
--    width = 2;
--    widget = LabelWidget({
--      init_func = function()
--        return model.getInfo().name
--      end;
--      label_flags = BOLD;
--    })
--  },
--
-- Options:
--
--   label: Use a simple string label.  If init_func is set, this is ignored
--   init_func: Call the given function and display it's returned value
--   label_flags: Flags are forwarded to drawText and can make the text bold,
--    at different sizes, etc.  See opentx docs for details.
local function LabelWidget(options)
  local label_flags = options.label_flags or 0
  local widget = {
    init = function(self)
      if options.init_func then
        self.label = options.init_func()
      else
        self.label = options.label
      end
    end;

    draw = function(self, rx, ry, rw, rh)
      lcd.drawText(rx, ry, self.label, label_flags)
    end
  }
  return widget
end


-- ValueWidget
--
-- Draws a labeled value.  By default, calls getValue for the value.  See the
-- OpenTX docs for available getValue strings.
--
-- Usage Example:
--
--  {
--    column = 0;
--    row = 1;
--    widget = ValueWidget('RS', {func=getRSSI})
--  },
--  {
--    column = 1;
--    row = 1;
--    widget = ValueWidget('tx-voltage', {label='TxV', decimals=1})
--  },
--
-- Options:
--
--   label: The label to put in front of the value.  If omitted, uses parm for
--     the label.
--   label_flags: Label draw flags (e.g. BOLD).  See OpenTX docs for drawText
--     for more information
--   value_flags: Value draw flags (e.g. BOLD).  See OpenTX docs for drawText
--     for more information
--   func: If set, calls this function for the value instead of getValue()
--   decimals: If set, rounds the output value to the given number of decimals.
--     e.g.  5.2345 becomes 5.23 if decimals = 2
local function ValueWidget(parm, options)
  local decimals = options.decimals or -1
  local label_flags = options.label_flags or 0
  local value_flags = options.value_flags or 0
  local label = options.label or parm
  value_flags = value_flags + RIGHT

  local func = function()
    local value = getValue(parm)
    if decimals >= 0 then
      local mult = 10^(decimals or 0)
      value = math.floor(value * mult + 0.5) / mult
    end
    return value
  end

  if options.func then
    func = options.func
  end

  local widget = {
    draw = function(self, rx, ry, rw, rh)
      lcd.drawText(rx, ry, label, label_flags)
      lcd.drawText(rx + rw, ry, func(), value_flags)
    end
  }
  return widget
end


-- SwitchWidget
--
-- Shows the value of a switch along with a custom label.  Can also
-- change style (e.g. bold, inverse, flashing) depending on state.
-- 
-- The idea is both to remind the pilot what switches are relevant and to show
-- if a switch is in a non-default state.
--
-- Example: Say you control rates via switch SC and want the default setting to
-- be high
--
--  {
--    column = 1;
--    row = 1;
--    widget = SwitchWidget('sc', {
--    labels = {'High', 'Low', 'Low'},
--    flags = {0, INVERS, INVERS}
--    })
--  },
--
-- The settings above will show High is SC if forward, and Low otherwise.
-- Also, the Low labels will be displayed in an inverse font
--
-- Options:
--
--   flags: Draw flags.  e.g. BOLD, INVERS
--   labels: Labels that correspond to each switch state
local function SwitchWidget(switch, options)
  local switch_pos_map = {
  {'sa', 3},
  {'sb', 3},
  {'sc', 3},
  {'sd', 3},
  {'se', 3},
  {'sf', 3},
  {'sg', 3},
  {'sh', 3},
  }

  local switch_idx = 1
  local switch_positions = 0
  for _, keyval in ipairs(switch_pos_map) do
  key, val = keyval[1], keyval[2]
    if key == switch then
      switch_positions = val
      break
    end
    switch_idx = switch_idx + val
  end

  if switch_positions == 0 then
    -- unknown switch
    return {}
  end

  local widget = {
  draw = function(self, rx, ry, rw, rh)
    local switch_val = (getValue(switch) + 1024) * (switch_positions - 1) / 2048
    flags = 0
    if options.flags then
    flags = options.flags[switch_val + 1]
    end
    lcd.drawSwitch(rx, ry, switch_idx + switch_val, flags)

    if not options.labels then
    return
    end

    flags = flags + RIGHT
    lcd.drawText(rx + rw, ry, options.labels[switch_val + 1], flags)
  end
  }
  return widget
end


-- TimerWidget
--
-- Shows the value of a timer.
--
-- Example:
--
--  {
--    column = 0;
--    row = 2;
--    widget = TimerWidget(0, {})
--  },
--
-- Options:
--
--   timer_flags: Display flags for timer.  e.g. BOLD, INVERS
--   label_flags: Display flags for "T0", "T1", or "T2" label
local function TimerWidget(timer_number, options)
  local label_flags = options.label_flags or 0
  local timer_flags = options.timer_flags or 0
  timer_flags = timer_flags + RIGHT
  local widget = {
  draw = function(self, rx, ry, rw, rh)
    local timer = model.getTimer(timer_number)
    lcd.drawText(rx, ry, "T" .. timer_number, label_flags)
    lcd.drawTimer(rx + rw + 3, ry, timer.value, timer_flags)
  end
  }
  return widget
end


-- LineWidget
--
-- Used to draw lines between other widgets for grouping.
--
-- Example:
--
--  {
--    column = 1;
--    row = 1;
--    height = 2;
--    width = 0;
--    pad = 0;
--    widget = LineWidget({})
--  },
--
-- Options:
--
-- pattern: Settings for drawLine pattern.  See openTX docs for details.
-- flags: Settings for drawLine flags.  See OpenTX docs for details.
local function LineWidget(options)
  local pattern = options.pattern or SOLID
  local flags = options.flags or FORCE
  local widget = {
  draw = function(self, rx, ry, rw, rh)
    lcd.drawLine(rx, ry, rx + rw, ry + rh, pattern, flags)
  end
  }
  return widget
end

--
-- Static Config
--
-- Optionally move these under CONFIG_START (or redefine them)
-- if you want to change the values.

-- Specifies how often you want data to be collected.
-- Units are in ms.
local BG_THROTTLE = {
  freq_ms = 100,  -- collect every 100ms (ten times a second)
  next_ms = 0
}

-- Specifies how often you want data to be displayed.  This should probably
-- be >= BG_THROTTLE to avoid pointless refreshes of identical data.
local RUN_THROTTLE = {
  freq_ms = 100,  -- display every 100ms
  next_ms = 0
}

--
-- CONFIG START
--

-- A basic placeholder config

resetGlobalVarIndex = -1

local genericSetup = {
  columns = {127};
  rows = {63};
  pad = 2;
  widgets = {
  {
    column = 0;
    row = 0;
    pad = 3;
    widget = RSSIHistogramWidget({})
  }}
}


local function chooseSetup()
  return genericSetup
end

--
-- CONFIG END
--

local Setup = nil

-- == Support Code ==


local function filterWidgets(widgets)
  local name = model.getInfo().name
  local filtered = {}
  for _, w in ipairs(widgets) do
  local include = true

  if include and w.only_models then
    include = false
    for _, mname in ipairs(w.only_models) do
    if name == mname then
      include = true
    end
    end
  end

  if include and w.not_models then
    for _, mname in ipairs(w.not_models) do
    if name == mname then
      include = false
    end
    end
  end

  if include then
    filtered[#filtered + 1] = w
  end
  end

  return filtered
end

local function filterSetup(setup)
  filtered = {}
  for key, val in pairs(setup) do
  if key == 'widgets' then
    filtered.widgets = filterWidgets(val)
  else
    filtered[key] = val
  end
  end
  return filtered
end

local function initFunc()
  Setup = filterSetup(chooseSetup())

  for _, w in ipairs(Setup.widgets) do
  if w.widget.init then
    w.widget:init()
  end
  end

  if resetGlobalVarIndex >= 0 then
    -- Set only for flight mode zero.  See if anyone cares?
    model.setGlobalVariable(resetGlobalVarIndex, 0, 0)
  end
end


local function isThrottled(throttle)
  local t_ms = getTime() * 10

  if t_ms < throttle.next_ms then
  return true
  end

  throttle.next_ms = t_ms + throttle.freq_ms
  return false
end


local function BGFunc()
  if isThrottled(BG_THROTTLE) then
    return
  end

  if resetGlobalVarIndex >= 0 then
    if model.getGlobalVariable(resetGlobalVarIndex, 0) ~= 0 then
      initFunc()
    end
  end
  
  -- Call each registered bg function
  for _, w in ipairs(Setup.widgets) do
  if w.widget.bg then
    w.widget:bg()
  end
  end
end

-- Return bounding box in pixels
local function getBoundingBox(widget)
  local rx = 0
  if widget.column > 0 then
  rx = Setup.columns[widget.column]
  end

  local ry = 0
  if widget.row > 0 then
  ry = Setup.rows[widget.row]
  end

  local cellw = widget.width or 1
  local rw = Setup.columns[widget.column + cellw] - rx

  local cellh = widget.height or 1
  local rh = Setup.rows[widget.row + cellh] - ry

  local pad = widget.pad or Setup.pad

  return rx + pad, ry + pad , rw - (pad * 2) , rh - (pad * 2)
end

local function runFunc(event)
  if isThrottled(RUN_THROTTLE) then
  return
  end

  lcd.clear()

  -- Call each registered draw function
  for _, w in ipairs(Setup.widgets) do
    if w.widget.draw then
      local rx, ry, rw, rh = getBoundingBox(w)
      w.widget:draw(rx, ry, rw, rh)
    end
  end
end



-- Return handlers
return { init=initFunc, background=BGFunc, run=runFunc }
