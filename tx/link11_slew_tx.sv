module link11_slew_tx (
    input wire clk,
    input 
);
/*
 自认为的发送端顺序:
 原始bit(header, data) + crc + 卷积编码 + interleave + 2dibit gray -> 左移1bit + 加扰 -> 8psk
 preamble无加扰无交织
 eom无卷积编码crc
*/


// 原始数据生成 header33/data48 + 12crc 前导码 192

// crc校验生成 前导码 EOM 不CRC

// 卷积编码  前导码 EOM不卷积编码, header 1/2 data 2/3

// 交织      前导码不交织

// 组2bit, 格雷映射, 左移变3bit

// 加扰       前导码不加扰

// 8PSK查找表

// 1800Hz频偏

endmodule