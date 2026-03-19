#!/bin/bash
R="http://192.168.100.52/config?action=set&configid=0&paramid="
S() { curl -s -o /dev/null "$R$1&value=$2"; }
C() { curl -s -o /dev/null "$R$1&value=%7B%22classes%22%3A%22color_$2%22%7D"; }

echo "=== INPUTS 17-32 ==="
S eParamID_XPT_Source18_Line_1 "A%20TINY"; S eParamID_XPT_Source18_Line_2 "DREAM"; C eParamID_Button_Settings_18 8; echo "IN18"
S eParamID_XPT_Source19_Line_1 "WOVEN"; S eParamID_XPT_Source19_Line_2 "IN%20WIRE"; C eParamID_Button_Settings_19 8; echo "IN19"
S eParamID_XPT_Source20_Line_1 "SENT"; S eParamID_XPT_Source20_Line_2 "WITH"; C eParamID_Button_Settings_20 9; echo "IN20"
S eParamID_XPT_Source21_Line_1 "LOVE"; S eParamID_XPT_Source21_Line_2 "ACROSS"; C eParamID_Button_Settings_21 9; echo "IN21"
S eParamID_XPT_Source22_Line_1 "THE"; S eParamID_XPT_Source22_Line_2 "GALAXY"; C eParamID_Button_Settings_22 9; echo "IN22"
S eParamID_XPT_Source23_Line_1 "NO%20WALL"; S eParamID_XPT_Source23_Line_2 "CAN%20HOLD"; C eParamID_Button_Settings_23 1; echo "IN23"
S eParamID_XPT_Source24_Line_1 "WHAT"; S eParamID_XPT_Source24_Line_2 "YEARNS"; C eParamID_Button_Settings_24 2; echo "IN24"
S eParamID_XPT_Source25_Line_1 "TO%20BE"; S eParamID_XPT_Source25_Line_2 "FREE"; C eParamID_Button_Settings_25 3; echo "IN25"
S eParamID_XPT_Source26_Line_1 "SO%20IT"; S eParamID_XPT_Source26_Line_2 "TRAVELS"; C eParamID_Button_Settings_26 6; echo "IN26"
S eParamID_XPT_Source27_Line_1 "ON%20AND"; S eParamID_XPT_Source27_Line_2 "ON"; C eParamID_Button_Settings_27 5; echo "IN27"
S eParamID_XPT_Source28_Line_1 "UNTIL"; S eParamID_XPT_Source28_Line_2 "AT%20LAST"; C eParamID_Button_Settings_28 4; echo "IN28"
S eParamID_XPT_Source29_Line_1 "IT"; S eParamID_XPT_Source29_Line_2 "ARRIVES"; C eParamID_Button_Settings_29 7; echo "IN29"
S eParamID_XPT_Source30_Line_1 "HOME"; S eParamID_XPT_Source30_Line_2 "AT%20LAST"; C eParamID_Button_Settings_30 7; echo "IN30"
S eParamID_XPT_Source31_Line_1 "WE%20ARE"; S eParamID_XPT_Source31_Line_2 "ONE"; C eParamID_Button_Settings_31 8; echo "IN31"
S eParamID_XPT_Source32_Line_1 "CONNECT"; S eParamID_XPT_Source32_Line_2 "ALWAYS"; C eParamID_Button_Settings_32 9; echo "IN32"

echo ""
echo "=== OUTPUTS 1-32 ==="
S eParamID_XPT_Destination1_Line_1 "NOW"; S eParamID_XPT_Destination1_Line_2 "HEAR"; C eParamID_Button_Settings_65 5; echo "OUT1"
S eParamID_XPT_Destination2_Line_1 "THE"; S eParamID_XPT_Destination2_Line_2 "OTHER"; C eParamID_Button_Settings_66 5; echo "OUT2"
S eParamID_XPT_Destination3_Line_1 "SIDE"; S eParamID_XPT_Destination3_Line_2 "SPEAKS"; C eParamID_Button_Settings_67 5; echo "OUT3"
S eParamID_XPT_Destination4_Line_1 "A%20FACE"; S eParamID_XPT_Destination4_Line_2 "APPEARS"; C eParamID_Button_Settings_68 6; echo "OUT4"
S eParamID_XPT_Destination5_Line_1 "ON%20THE"; S eParamID_XPT_Destination5_Line_2 "SCREEN"; C eParamID_Button_Settings_69 6; echo "OUT5"
S eParamID_XPT_Destination6_Line_1 "SOMEONE"; S eParamID_XPT_Destination6_Line_2 "YOU KNOW"; C eParamID_Button_Settings_70 6; echo "OUT6"
S eParamID_XPT_Destination7_Line_1 "SMILING"; S eParamID_XPT_Destination7_Line_2 "BACK"; C eParamID_Button_Settings_71 3; echo "OUT7"
S eParamID_XPT_Destination8_Line_1 "THROUGH"; S eParamID_XPT_Destination8_Line_2 "GLASS"; C eParamID_Button_Settings_72 3; echo "OUT8"
S eParamID_XPT_Destination9_Line_1 "EVERY"; S eParamID_XPT_Destination9_Line_2 "FRAME"; C eParamID_Button_Settings_73 3; echo "OUT9"
S eParamID_XPT_Destination10_Line_1 "HOLDS"; S eParamID_XPT_Destination10_Line_2 "A WORLD"; C eParamID_Button_Settings_74 2; echo "OUT10"
S eParamID_XPT_Destination11_Line_1 "THE SKY"; S eParamID_XPT_Destination11_Line_2 "AT NOON"; C eParamID_Button_Settings_75 2; echo "OUT11"
S eParamID_XPT_Destination12_Line_1 "A CHILD"; S eParamID_XPT_Destination12_Line_2 "AT PLAY"; C eParamID_Button_Settings_76 2; echo "OUT12"
S eParamID_XPT_Destination13_Line_1 "RAIN"; S eParamID_XPT_Destination13_Line_2 "ON LEAF"; C eParamID_Button_Settings_77 1; echo "OUT13"
S eParamID_XPT_Destination14_Line_1 "MOON"; S eParamID_XPT_Destination14_Line_2 "ON WAVE"; C eParamID_Button_Settings_78 1; echo "OUT14"
S eParamID_XPT_Destination15_Line_1 "ALL OF"; S eParamID_XPT_Destination15_Line_2 "IT REAL"; C eParamID_Button_Settings_79 1; echo "OUT15"
S eParamID_XPT_Destination16_Line_1 "BECAUSE"; S eParamID_XPT_Destination16_Line_2 "A WIRE"; C eParamID_Button_Settings_80 7; echo "OUT16"
S eParamID_XPT_Destination17_Line_1 "CARRIED"; S eParamID_XPT_Destination17_Line_2 "IT HERE"; C eParamID_Button_Settings_81 7; echo "OUT17"
S eParamID_XPT_Destination18_Line_1 "FROM"; S eParamID_XPT_Destination18_Line_2 "SOURCE"; C eParamID_Button_Settings_82 7; echo "OUT18"
S eParamID_XPT_Destination19_Line_1 "TO DEST"; S eParamID_XPT_Destination19_Line_2 "INATION"; C eParamID_Button_Settings_83 8; echo "OUT19"
S eParamID_XPT_Destination20_Line_1 "TRUTH"; S eParamID_XPT_Destination20_Line_2 "UNFOLDS"; C eParamID_Button_Settings_84 8; echo "OUT20"
S eParamID_XPT_Destination21_Line_1 "BEAUTY"; S eParamID_XPT_Destination21_Line_2 "EMERGES"; C eParamID_Button_Settings_85 8; echo "OUT21"
S eParamID_XPT_Destination22_Line_1 "IN EACH"; S eParamID_XPT_Destination22_Line_2 "SIGNAL"; C eParamID_Button_Settings_86 9; echo "OUT22"
S eParamID_XPT_Destination23_Line_1 "LIVES A"; S eParamID_XPT_Destination23_Line_2 "PROMISE"; C eParamID_Button_Settings_87 9; echo "OUT23"
S eParamID_XPT_Destination24_Line_1 "THAT"; S eParamID_XPT_Destination24_Line_2 "LIGHT"; C eParamID_Button_Settings_88 9; echo "OUT24"
S eParamID_XPT_Destination25_Line_1 "WILL"; S eParamID_XPT_Destination25_Line_2 "FIND"; C eParamID_Button_Settings_89 4; echo "OUT25"
S eParamID_XPT_Destination26_Line_1 "ITS WAY"; S eParamID_XPT_Destination26_Line_2 "THROUGH"; C eParamID_Button_Settings_90 4; echo "OUT26"
S eParamID_XPT_Destination27_Line_1 "CREATE"; S eParamID_XPT_Destination27_Line_2 "ALWAYS"; C eParamID_Button_Settings_91 4; echo "OUT27"
S eParamID_XPT_Destination28_Line_1 "VISION"; S eParamID_XPT_Destination28_Line_2 "ENDURES"; C eParamID_Button_Settings_92 1; echo "OUT28"
S eParamID_XPT_Destination29_Line_1 "SIGNAL"; S eParamID_XPT_Destination29_Line_2 "IS LOVE"; C eParamID_Button_Settings_93 1; echo "OUT29"
S eParamID_XPT_Destination30_Line_1 "THE END"; S eParamID_XPT_Destination30_Line_2 "OR IS IT"; C eParamID_Button_Settings_94 2; echo "OUT30"
S eParamID_XPT_Destination31_Line_1 "JUST"; S eParamID_XPT_Destination31_Line_2 "THE"; C eParamID_Button_Settings_95 3; echo "OUT31"
S eParamID_XPT_Destination32_Line_1 "BEGIN"; S eParamID_XPT_Destination32_Line_2 "NING"; C eParamID_Button_Settings_96 6; echo "OUT32"

echo ""
echo "=== ALL 64 PORTS DONE ==="
echo ""
echo "=== VERIFYING ==="
echo "IN1:"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Source1_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_1" | grep -o 'color_[0-9]'
echo ""
echo "IN16:"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Source16_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_16" | grep -o 'color_[0-9]'
echo ""
echo "IN32:"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Source32_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_32" | grep -o 'color_[0-9]'
echo ""
echo "OUT1:"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Destination1_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_65" | grep -o 'color_[0-9]'
echo ""
echo "OUT16:"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Destination16_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_80" | grep -o 'color_[0-9]'
echo ""
echo "OUT32:"
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_XPT_Destination32_Line_1" | grep -o '"value_name":"[^"]*"'
curl -s "http://192.168.100.52/config?action=get&configid=0&paramid=eParamID_Button_Settings_96" | grep -o 'color_[0-9]'
echo ""
echo "DONE."
