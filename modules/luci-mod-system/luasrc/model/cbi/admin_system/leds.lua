-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

m = Map("system", translate("<abbr title=\"Light Emitting Diode\">LED</abbr> Configuration"), translate("Customizes the behaviour of the device <abbr title=\"Light Emitting Diode\">LED</abbr>s if possible."))

local sysfs_path = "/sys/class/leds/"
local leds = {}

local fs   = require "nixio.fs"
local nu   = require "nixio.util"
local util = require "luci.util"

if fs.access(sysfs_path) then
	leds = nu.consume((fs.dir(sysfs_path)))
end

if #leds == 0 then
	return m
end


s = m:section(TypedSection, "led", "")
s.anonymous = true
s.addremove = true

function s.parse(self, ...)
	TypedSection.parse(self, ...)
	os.execute("/etc/init.d/led enable")
end


s:option(Value, "name", translate("Name"))


sysfs = s:option(ListValue, "sysfs", translate("<abbr title=\"Light Emitting Diode\">LED</abbr> Name"))
for k, v in ipairs(leds) do
	sysfs:value(v)
end

s:option(Flag, "default", translate("Default state")).rmempty = false


trigger = s:option(ListValue, "trigger", translate("Trigger"))

local triggers = fs.readfile(sysfs_path .. leds[1] .. "/trigger")
for t in triggers:gmatch("[%w-]+") do
	if t == "default-on" then
		trigger:value(t, translatef("Always on (%s)", t))
	elseif t == "none" then
		trigger:value(t, translatef("Always off (%s)", t))
	elseif t == "timer" then
		trigger:value(t, translatef("Custom flash interval (%s)", t))
	elseif t == "netdev" then
		trigger:value(t, translatef("Network device activity (%s)", t))
	elseif t == "heartbeat" then
		trigger:value(t, translatef("Heartbeat interval (%s)", t))
	elseif t == "nand-disk" then
		trigger:value(t, translatef("Flash memory activity (%s)", t))
	elseif t == "mtd" then
		trigger:value(t, translatef("Flash memory activity (%s)", t))
	elseif t:match("mmc[0-9]") then
		trigger:value(t, translatef("Flash memory activity (%s)", t))
	elseif t:match("switch[0-9]") then
		trigger:value(t, translatef("Switchport activity (%s)", t))
	elseif t:match("phy[0-9]rx") then
		trigger:value(t, translatef("Wi-Fi data reception (%s)", t))
	elseif t:match("phy[0-9]tx") then
		trigger:value(t, translatef("Wi-Fi data transmission (%s)", t))
	elseif t:match("phy[0-9]assoc") then
		trigger:value(t, translatef("Wi-Fi client association (%s)", t))
	elseif t:match("phy[0-9]radio") then
		trigger:value(t, translatef("Wi-Fi on (%s)", t))
	elseif t:match("phy[0-9]tpt") then
		trigger:value(t, translatef("Wi-Fi activity (%s)", t))
	else
		trigger:value(t, translate(t:gsub("-", "")))
	end
end


delayon = s:option(Value, "delayon", translate ("On-State Delay"))
delayon:depends("trigger", "timer")

delayoff = s:option(Value, "delayoff", translate ("Off-State Delay"))
delayoff:depends("trigger", "timer")


dev = s:option(Value, "_net_dev", translate("Device"))
dev.rmempty = true
dev:value("")
dev:depends("trigger", "netdev")

function dev.cfgvalue(self, section)
	return m.uci:get("system", section, "dev")
end

function dev.write(self, section, value)
	m.uci:set("system", section, "dev", value)
end

function dev.remove(self, section)
	local t = trigger:formvalue(section)
	if t ~= "netdev" and t ~= "usbdev" then
		m.uci:delete("system", section, "dev")
	end
end

for k, v in pairs(luci.sys.net.devices()) do
	if v ~= "lo" then
		dev:value(v)
	end
end


mode = s:option(MultiValue, "mode", translate("Trigger Mode"))
mode.rmempty = true
mode:depends("trigger", "netdev")
mode:value("link", translate("Link On"))
mode:value("tx", translate("Transmit"))
mode:value("rx", translate("Receive"))


usbdev = s:option(ListValue, "_usb_dev", translate("USB Device"))
usbdev:depends("trigger", "usbdev")
usbdev.rmempty = true
usbdev:value("")

function usbdev.cfgvalue(self, section)
	return m.uci:get("system", section, "dev")
end

function usbdev.write(self, section, value)
	m.uci:set("system", section, "dev", value)
end

function usbdev.remove(self, section)
	local t = trigger:formvalue(section)
	if t ~= "netdev" and t ~= "usbdev" then
		m.uci:delete("system", section, "dev")
	end
end


usbport = s:option(MultiValue, "port", translate("USB Ports"))
usbport:depends("trigger", "usbport")
usbport.rmempty = true
usbport.widget = "checkbox"
usbport.cast = "table"
usbport.size = 1

function usbport.valuelist(self, section)
	local port, ports = nil, {}
	for port in util.imatch(m.uci:get("system", section, "port")) do
		local b, n = port:match("^usb(%d+)-port(%d+)$")
		if not (b and n) then
			b, n = port:match("^(%d+)-(%d+)$")
		end
		if b and n then
			ports[#ports+1] = "usb%u-port%u" %{ tonumber(b), tonumber(n) }
		end
	end
	return ports
end

function usbport.validate(self, value)
	return type(value) == "string" and { value } or value
end


for p in nixio.fs.glob("/sys/bus/usb/devices/[0-9]*/manufacturer") do
	local id = p:match("%d+-%d+")
	local mf = nixio.fs.readfile("/sys/bus/usb/devices/" .. id .. "/manufacturer") or "?"
	local pr = nixio.fs.readfile("/sys/bus/usb/devices/" .. id .. "/product")      or "?"
	usbdev:value(id, "%s (%s - %s)" %{ id, mf, pr })
end

for p in nixio.fs.glob("/sys/bus/usb/devices/*/usb[0-9]*-port[0-9]*") do
	local bus, port = p:match("usb(%d+)-port(%d+)")
	if bus and port then
		usbport:value("usb%u-port%u" %{ tonumber(bus), tonumber(port) },
		              "Hub %u, Port %u" %{ tonumber(bus), tonumber(port) })
	end
end

port_mask = s:option(Value, "port_mask", translate ("Switch Port Mask"))
port_mask:depends("trigger", "switch0")

return m
