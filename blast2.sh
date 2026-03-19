#!/bin/bash
# CORRECTED blast script:
# 1. Escaped quotes in color value: {\"classes\":\"color_N\"}
# 2. Correct Button_Settings mapping:
#    Src 1-16  -> Button 1-16
#    Dst 1-16  -> Button 17-32
#    Src 17-32 -> Button 33-48
#    Dst 17-32 -> Button 49-64

R="http://192.168.100.52/config?action=set&configid=0&paramid="

# Set label (line1 or line2)
S() { curl -s -o /dev/null "$R$1&value=$2"; }

# Set color with ESCAPED quotes
C() { curl -s -o /dev/null "$R$1&value=%7B%5C%22classes%5C%22%3A%5C%22color_$2%5C%22%7D"; }

echo "=== SOURCES 1-16 (Button 1-16) ==="
S eParamID_XPT_Source1_Line_1 "ONCE"; S eParamID_XPT_Source1_Line_2 "UPON%20A"; C eParamID_Button_Settings_1 1; echo "S1"
S eParamID_XPT_Source2_Line_1 "TIME"; S eParamID_XPT_Source2_Line_2 "THERE"; C eParamID_Button_Settings_2 1; echo "S2"
S eParamID_XPT_Source3_Line_1 "WAS%20A"; S eParamID_XPT_Source3_Line_2 "SIGNAL"; C eParamID_Button_Settings_3 2; echo "S3"
S eParamID_XPT_Source4_Line_1 "BORN"; S eParamID_XPT_Source4_Line_2 "OF%20FIRE"; C eParamID_Button_Settings_4 2; echo "S4"
S eParamID_XPT_Source5_Line_1 "IN%20THE"; S eParamID_XPT_Source5_Line_2 "DARK"; C eParamID_Button_Settings_5 3; echo "S5"
S eParamID_XPT_Source6_Line_1 "IT%20ROSE"; S eParamID_XPT_Source6_Line_2 "SLOWLY"; C eParamID_Button_Settings_6 3; echo "S6"
S eParamID_XPT_Source7_Line_1 "THROUGH"; S eParamID_XPT_Source7_Line_2 "THE%20VOID"; C eParamID_Button_Settings_7 5; echo "S7"
S eParamID_XPT_Source8_Line_1 "A%20SPARK"; S eParamID_XPT_Source8_Line_2 "OF%20GOLD"; C eParamID_Button_Settings_8 5; echo "S8"
S eParamID_XPT_Source9_Line_1 "BECAME"; S eParamID_XPT_Source9_Line_2 "A%20RIVER"; C eParamID_Button_Settings_9 6; echo "S9"
S eParamID_XPT_Source10_Line_1 "OF%20PURE"; S eParamID_XPT_Source10_Line_2 "LIGHT"; C eParamID_Button_Settings_10 6; echo "S10"
S eParamID_XPT_Source11_Line_1 "FLOWING"; S eParamID_XPT_Source11_Line_2 "EAST"; C eParamID_Button_Settings_11 7; echo "S11"
S eParamID_XPT_Source12_Line_1 "TOWARD"; S eParamID_XPT_Source12_Line_2 "THE%20SEA"; C eParamID_Button_Settings_12 7; echo "S12"
S eParamID_XPT_Source13_Line_1 "WHERE"; S eParamID_XPT_Source13_Line_2 "WAVES"; C eParamID_Button_Settings_13 8; echo "S13"
S eParamID_XPT_Source14_Line_1 "CARRY"; S eParamID_XPT_Source14_Line_2 "STORIES"; C eParamID_Button_Settings_14 8; echo "S14"
S eParamID_XPT_Source15_Line_1 "FROM%20ONE"; S eParamID_XPT_Source15_Line_2 "SHORE"; C eParamID_Button_Settings_15 9; echo "S15"
S eParamID_XPT_Source16_Line_1 "TO%20THE"; S eParamID_XPT_Source16_Line_2 "OTHER"; C eParamID_Button_Settings_16 9; echo "S16"

echo ""
echo "=== SOURCES 17-32 (Button 33-48) ==="
S eParamID_XPT_Source17_Line_1 "EACH"; S eParamID_XPT_Source17_Line_2 "PIXEL"; C eParamID_Button_Settings_33 1; echo "S17"
S eParamID_XPT_Source18_Line_1 "A%20TINY"; S eParamID_XPT_Source18_Line_2 "DREAM"; C eParamID_Button_Settings_34 1; echo "S18"
S eParamID_XPT_Source19_Line_1 "WOVEN"; S eParamID_XPT_Source19_Line_2 "IN%20WIRE"; C eParamID_Button_Settings_35 2; echo "S19"
S eParamID_XPT_Source20_Line_1 "SENT"; S eParamID_XPT_Source20_Line_2 "WITH"; C eParamID_Button_Settings_36 2; echo "S20"
S eParamID_XPT_Source21_Line_1 "LOVE"; S eParamID_XPT_Source21_Line_2 "ACROSS"; C eParamID_Button_Settings_37 3; echo "S21"
S eParamID_XPT_Source22_Line_1 "THE"; S eParamID_XPT_Source22_Line_2 "GALAXY"; C eParamID_Button_Settings_38 3; echo "S22"
S eParamID_XPT_Source23_Line_1 "NO%20WALL"; S eParamID_XPT_Source23_Line_2 "CAN%20HOLD"; C eParamID_Button_Settings_39 5; echo "S23"
S eParamID_XPT_Source24_Line_1 "WHAT"; S eParamID_XPT_Source24_Line_2 "YEARNS"; C eParamID_Button_Settings_40 5; echo "S24"
S eParamID_XPT_Source25_Line_1 "TO%20BE"; S eParamID_XPT_Source25_Line_2 "FREE"; C eParamID_Button_Settings_41 6; echo "S25"
S eParamID_XPT_Source26_Line_1 "SO%20IT"; S eParamID_XPT_Source26_Line_2 "TRAVELS"; C eParamID_Button_Settings_42 6; echo "S26"
S eParamID_XPT_Source27_Line_1 "ON%20AND"; S eParamID_XPT_Source27_Line_2 "ON"; C eParamID_Button_Settings_43 7; echo "S27"
S eParamID_XPT_Source28_Line_1 "UNTIL"; S eParamID_XPT_Source28_Line_2 "AT%20LAST"; C eParamID_Button_Settings_44 7; echo "S28"
S eParamID_XPT_Source29_Line_1 "IT"; S eParamID_XPT_Source29_Line_2 "ARRIVES"; C eParamID_Button_Settings_45 8; echo "S29"
S eParamID_XPT_Source30_Line_1 "HOME"; S eParamID_XPT_Source30_Line_2 "AT%20LAST"; C eParamID_Button_Settings_46 8; echo "S30"
S eParamID_XPT_Source31_Line_1 "WE%20ARE"; S eParamID_XPT_Source31_Line_2 "ONE"; C eParamID_Button_Settings_47 9; echo "S31"
S eParamID_XPT_Source32_Line_1 "CONNECT"; S eParamID_XPT_Source32_Line_2 "ALWAYS"; C eParamID_Button_Settings_48 9; echo "S32"

echo ""
echo "=== DESTINATIONS 1-16 (Button 17-32) ==="
S eParamID_XPT_Destination1_Line_1 "NOW"; S eParamID_XPT_Destination1_Line_2 "HEAR"; C eParamID_Button_Settings_17 5; echo "D1"
S eParamID_XPT_Destination2_Line_1 "THE"; S eParamID_XPT_Destination2_Line_2 "OTHER"; C eParamID_Button_Settings_18 5; echo "D2"
S eParamID_XPT_Destination3_Line_1 "SIDE"; S eParamID_XPT_Destination3_Line_2 "SPEAKS"; C eParamID_Button_Settings_19 6; echo "D3"
S eParamID_XPT_Destination4_Line_1 "A%20FACE"; S eParamID_XPT_Destination4_Line_2 "APPEARS"; C eParamID_Button_Settings_20 6; echo "D4"
S eParamID_XPT_Destination5_Line_1 "ON%20THE"; S eParamID_XPT_Destination5_Line_2 "SCREEN"; C eParamID_Button_Settings_21 3; echo "D5"
S eParamID_XPT_Destination6_Line_1 "SOMEONE"; S eParamID_XPT_Destination6_Line_2 "YOU%20KNOW"; C eParamID_Button_Settings_22 3; echo "D6"
S eParamID_XPT_Destination7_Line_1 "SMILING"; S eParamID_XPT_Destination7_Line_2 "BACK"; C eParamID_Button_Settings_23 8; echo "D7"
S eParamID_XPT_Destination8_Line_1 "THROUGH"; S eParamID_XPT_Destination8_Line_2 "GLASS"; C eParamID_Button_Settings_24 8; echo "D8"
S eParamID_XPT_Destination9_Line_1 "EVERY"; S eParamID_XPT_Destination9_Line_2 "FRAME"; C eParamID_Button_Settings_25 9; echo "D9"
S eParamID_XPT_Destination10_Line_1 "HOLDS"; S eParamID_XPT_Destination10_Line_2 "A%20WORLD"; C eParamID_Button_Settings_26 9; echo "D10"
S eParamID_XPT_Destination11_Line_1 "THE%20SKY"; S eParamID_XPT_Destination11_Line_2 "AT%20NOON"; C eParamID_Button_Settings_27 1; echo "D11"
S eParamID_XPT_Destination12_Line_1 "A%20CHILD"; S eParamID_XPT_Destination12_Line_2 "AT%20PLAY"; C eParamID_Button_Settings_28 1; echo "D12"
S eParamID_XPT_Destination13_Line_1 "RAIN"; S eParamID_XPT_Destination13_Line_2 "ON%20LEAF"; C eParamID_Button_Settings_29 2; echo "D13"
S eParamID_XPT_Destination14_Line_1 "MOON"; S eParamID_XPT_Destination14_Line_2 "ON%20WAVE"; C eParamID_Button_Settings_30 2; echo "D14"
S eParamID_XPT_Destination15_Line_1 "ALL%20OF"; S eParamID_XPT_Destination15_Line_2 "IT%20REAL"; C eParamID_Button_Settings_31 7; echo "D15"
S eParamID_XPT_Destination16_Line_1 "BECAUSE"; S eParamID_XPT_Destination16_Line_2 "A%20WIRE"; C eParamID_Button_Settings_32 7; echo "D16"

echo ""
echo "=== DESTINATIONS 17-32 (Button 49-64) ==="
S eParamID_XPT_Destination17_Line_1 "CARRIED"; S eParamID_XPT_Destination17_Line_2 "IT%20HERE"; C eParamID_Button_Settings_49 5; echo "D17"
S eParamID_XPT_Destination18_Line_1 "FROM"; S eParamID_XPT_Destination18_Line_2 "SOURCE"; C eParamID_Button_Settings_50 5; echo "D18"
S eParamID_XPT_Destination19_Line_1 "TO%20DEST"; S eParamID_XPT_Destination19_Line_2 "INATION"; C eParamID_Button_Settings_51 6; echo "D19"
S eParamID_XPT_Destination20_Line_1 "TRUTH"; S eParamID_XPT_Destination20_Line_2 "UNFOLDS"; C eParamID_Button_Settings_52 6; echo "D20"
S eParamID_XPT_Destination21_Line_1 "BEAUTY"; S eParamID_XPT_Destination21_Line_2 "EMERGES"; C eParamID_Button_Settings_53 3; echo "D21"
S eParamID_XPT_Destination22_Line_1 "IN%20EACH"; S eParamID_XPT_Destination22_Line_2 "SIGNAL"; C eParamID_Button_Settings_54 3; echo "D22"
S eParamID_XPT_Destination23_Line_1 "LIVES%20A"; S eParamID_XPT_Destination23_Line_2 "PROMISE"; C eParamID_Button_Settings_55 8; echo "D23"
S eParamID_XPT_Destination24_Line_1 "THAT"; S eParamID_XPT_Destination24_Line_2 "LIGHT"; C eParamID_Button_Settings_56 8; echo "D24"
S eParamID_XPT_Destination25_Line_1 "WILL"; S eParamID_XPT_Destination25_Line_2 "FIND"; C eParamID_Button_Settings_57 9; echo "D25"
S eParamID_XPT_Destination26_Line_1 "ITS%20WAY"; S eParamID_XPT_Destination26_Line_2 "THROUGH"; C eParamID_Button_Settings_58 9; echo "D26"
S eParamID_XPT_Destination27_Line_1 "CREATE"; S eParamID_XPT_Destination27_Line_2 "ALWAYS"; C eParamID_Button_Settings_59 1; echo "D27"
S eParamID_XPT_Destination28_Line_1 "VISION"; S eParamID_XPT_Destination28_Line_2 "ENDURES"; C eParamID_Button_Settings_60 1; echo "D28"
S eParamID_XPT_Destination29_Line_1 "SIGNAL"; S eParamID_XPT_Destination29_Line_2 "IS%20LOVE"; C eParamID_Button_Settings_61 2; echo "D29"
S eParamID_XPT_Destination30_Line_1 "THE%20END"; S eParamID_XPT_Destination30_Line_2 "OR%20IS%20IT"; C eParamID_Button_Settings_62 2; echo "D30"
S eParamID_XPT_Destination31_Line_1 "JUST"; S eParamID_XPT_Destination31_Line_2 "THE"; C eParamID_Button_Settings_63 7; echo "D31"
S eParamID_XPT_Destination32_Line_1 "BEGIN"; S eParamID_XPT_Destination32_Line_2 "NING"; C eParamID_Button_Settings_64 7; echo "D32"

echo ""
echo "=== ALL 64 PORTS DONE ==="
echo ""
echo "=== VERIFYING ==="

echo "S1 (Button 1):"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Source1_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_1" | grep -o '"classes\\":\\"color_[0-9]'
echo ""

echo "S17 (Button 33):"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Source17_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_33" | grep -o '"classes\\":\\"color_[0-9]'
echo ""

echo "D1 (Button 17):"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Destination1_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_17" | grep -o '"classes\\":\\"color_[0-9]'
echo ""

echo "D17 (Button 49):"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Destination17_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_49" | grep -o '"classes\\":\\"color_[0-9]'
echo ""

echo "D32 (Button 64):"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Destination32_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_64" | grep -o '"classes\\":\\"color_[0-9]'
echo ""

echo "DONE."
