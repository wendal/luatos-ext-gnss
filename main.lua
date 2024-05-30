
_G.sys = require("sys")
require "sysplus"
--[[
星历格式分析
1. Air780EP星历   http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat
2. Air780EPVH星历 http://download.openluat.com/9501-xingli/HD_GPS_BDS.hdb
3. Air530Z-BD星历 http://download.openluat.com/9501-xingli/CASIC_data.dat
]]

function rtcm_decode(path)
    
    -- HXXT是RTCM3.2 格式
    -- 参考链接 http://www.bynav.cn/media/upload/cms_15/AN018_RTCM3.2%E6%A0%BC%E5%BC%8F%E8%AF%B4%E6%98%8E_%E5%8C%97%E4%BA%91%E7%A7%91%E6%8A%80.pdf
    local hxxt = io.readFile(path)
    hxxt = zbuff.create(#hxxt, hxxt)
    hxxt:seek(0)

    local count = 0
    while hxxt:used() < hxxt:len() do
        -- 首先是D3
        local d3 = hxxt:readU8(1)
        if d3 == 0xD3 then
            count = count + 1
            -- log.info("数据帧头部正确")
            local len = hxxt:readU8() * 256 + hxxt:readU8()
            local data = hxxt:read(len)
            local crc = hxxt:read(3)
            -- log.info("数据帧", "长度", len, "CRC", crc:toHex())
            -- 解析数据
            local msg = zbuff.create(#data, data)
            msg:seek(0)
            local msgh = (msg:readU8() << 16) + (msg:readU8() << 8) + msg:readU8()
            local msgtype = msgh >> (12)
            -- log.info("数据帧", "消息类型", msgtype, data:sub(1, 16):toHex())
            if msgtype == 1019 or msgtype == 63 then
                -- 卫星编号
                local svid = (msgh >> 6) & ((1 << 6) - 1)
                log.info("数据帧", msgtype == 1019 and "GPS星历" or "BDS星历", "卫星编号", svid, data:sub(1, 16):toHex())
            else
                log.info("数据帧", "消息类型", msgtype, data:sub(1, 16):toHex())
            end
        else
            log.error("格式错误", string.format("%04X %02X", hxxt:used(), d3))
            -- break
        end
    end
    log.info("解析完毕", "数量", count)
end

function zkw_decode(path)
    
    -- 中科微的星历格式, 跟它的二进制协议是一样的
    local hxxt = io.readFile(path)
    hxxt = zbuff.create(#hxxt, hxxt)
    hxxt:seek(0)

    local count = 0
    while hxxt:used() < hxxt:len() do
        -- 首先是D3
        local magic = hxxt:readU8() * 256 + hxxt:readU8()
        if magic == 0xBACE then
            count = count + 1
            -- log.info("数据帧头部正确")
            local len = hxxt:readU8() + hxxt:readU8() * 256
            local data = hxxt:read(len + 2)
            local crc = hxxt:read(4)
            local crc2 = 0
            local tmpdata = string.char(len & 0xFF, len >>8) .. data
            for i = 1, #tmpdata, 4 do
                crc2 = crc2 + tmpdata:byte(i) + (tmpdata:byte(i+1) << 8)+ (tmpdata:byte(i+2) << 16)+ (tmpdata:byte(i+3) << 24)
            end
            -- log.info("数据帧", "长度", len, "CRC", crc:toHex(), string.pack("<I", crc2):toHex())
            -- log.info("临时校验", tmpdata:toHex())
            -- 解析数据
            local msg = zbuff.create(#data, data)
            msg:seek(0)
            local msgtype = msg:readU8()
            local msgid = msg:readU8()
            -- log.info("数据帧", msgtype, msgid, data:toHex())
            -- 北斗星历系列
            if msgtype == 0x08 and msgid == 0x02 then
                msg:seek(89)
                local health = msg:readU8()
                local svid = msg:readU8()
                local valid = msg:readU8()
                msg:seek(2)
                -- 4字节保留
                msg:read(4)
                -- 卫星轨道半长轴的平方根
                msg:read(4)
                -- 卫星轨道偏心率
                local px = string.unpack("<f", msg:read(4))
                -- 近地点幅角
                msg:read(4)

                -- 星历参考时刻
                msg:seek(62)
                local rtime = string.unpack("<I", msg:read(4))
                local rweek = string.unpack("<H", msg:read(2))
                log.info("数据帧", "MSG-BDSEPH 北斗星历", "卫星编号", svid, "可用", valid, "参考时刻", rtime, rweek)
            end
            if msgtype == 0x08 and msgid == 0x01 then
                log.info("数据帧", "MSG-BDSION 北斗电离层参数")
            end
            if msgtype == 0x08 and msgid == 0x00 then
                log.info("数据帧", "MSG-BDSUTC 北斗定点UTC")
            end

            -- GPS星历系列
            if msgtype == 0x08 and msgid == 0x07 then
                msg:seek(70)
                local svid = msg:readU8()
                local valid = msg:readU8()
                -- log.info("数据帧", msgtype, msgid, data:toHex())
                log.info("数据帧", "MSG-GPSEPH GPS星历", "卫星编号", svid, "可用", valid)
            end
            if msgtype == 0x08 and msgid == 0x06 then
                log.info("数据帧", "MSG-GPSION GPS电离层参数")
            end
            if msgtype == 0x08 and msgid == 0x05 then
                log.info("数据帧", "MSG-GPSUTC GPS定点UTC")
            end
        else
            log.error("格式错误", string.format("%04X %04X", hxxt:used(), magic))
            -- break
        end
    end
    log.info("解析完毕", "数量", count)
end


function hd_decode(path)
    
    -- 中科微的星历格式, 跟它的二进制协议是一样的
    local hxxt = io.readFile(path)
    hxxt = zbuff.create(#hxxt, hxxt)
    hxxt:seek(0)

    local count = 0
    while hxxt:used() < hxxt:len() do
        -- 首先是F1
        local magic = hxxt:readU8() * 256 + hxxt:readU8()
        if magic == 0xF1D9 then
            count = count + 1
            -- log.info("数据帧头部正确")
            local msgg = hxxt:readU8()
            local msgs = hxxt:readU8()
            local len = hxxt:readU8() + hxxt:readU8() * 256
            local data = hxxt:read(len)
            local crc = hxxt:read(2)
            -- log.info("数据帧", string.format("%02X %02X", msgg, msgs), "长度", len)
            if msgg == 0x0B then
                -- 星历信息
                local msg = zbuff.create(#data, data)
                local msgc = 0
                local msgz = 0
                msg:seek(0)
                local gsys = "未知"
                if msgs == 0x32 then
                    gsys = "GPS"
                    msgz = 65
                    msgc = #data // 65
                elseif msgs == 0x33 then
                    gsys = "BDS"
                    msgz = 92
                    msgc = #data // 92
                end
                if msgc > 0 then
                    for i = 1, msgc do
                        -- 第一个字节是保留的, 不知道是啥, tiaog
                        msg:read(1)
                        -- 第二个字节的是卫星编号
                        local svid = msg:readU8()
                        -- 跳过剩余字节
                        msg:read(msgz - 2)
                        log.info("华大星历", gsys, "卫星编号", svid, string.format("%04X", msg:used()))
                    end
                
                end
            else
                log.info("华大星历", "未知数据帧", string.format("%02X %02X", msgg, msgs), "长度", len)
            end
        else
            log.error("格式错误", string.format("%04X %04X", hxxt:used(), magic))
            break
        end
    end
    log.info("解析完毕", "数量", count)
end

sys.taskInit(function()
    -- sys.waitUntil("IP_READY",30000)
    if nil then
    -- if not io.exists("/HXXT.dat") then
        local code = http.request("GET", "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat", nil, nil, {dst="/HXXT.dat"}).wait()
        log.info("http", code)
    -- end
    -- if not io.exists("/HD_GPS_BDS.dat") then
        local code = http.request("GET", "http://download.openluat.com/9501-xingli/HD_GPS_BDS.hdb", nil, nil, {dst="/HD_GPS_BDS.dat"}).wait()
        log.info("http", code)
    -- end
    -- if not io.exists("/ZKW2.dat") then
        local code = http.request("GET", "http://download.openluat.com/9501-xingli/CASIC_data.dat", nil, nil, {dst="/ZKW2.dat"}).wait()
        log.info("http", code)
    -- end
    -- if not io.exists("/ZKW_bds.dat") then
        local code = http.request("GET", "http://download.openluat.com/9501-xingli/CASIC_data_bds.dat", nil, nil, {dst="/ZKW_bds.dat"}).wait()
        log.info("http", code)
    -- end
    end

    log.info("GNSS","解码6228的星历, RTCM 3.2格式")
    -- rtcm_decode("/HXXT.dat")
    -- rtcm_decode("/HD.dat")
    log.info("GNSS","解码中科微的星历, 厂商自定义格式")
    -- zkw_decode("/ZKW2.dat") -- GPS+北斗
    -- zkw_decode("/ZKW_bds.dat") -- 单北斗

    log.info("GNSS","解码华大的星历, 厂商自定义格式")
    hd_decode("/HD_GPS_BDS.hdb")
    os.exit()
end)

sys.run()
