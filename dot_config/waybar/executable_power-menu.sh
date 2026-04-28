#!/bin/bash
# Power menu using wofi

chosen=$(echo -e "Lock Screen\nShutdown\nReboot\nSuspend\nHibernate" | wofi --show dmenu --prompt "Power" --location center --width 200 --height 300)

case $chosen in
    "Lock Screen") swaylock ;;
    Shutdown) systemctl poweroff ;;
    Reboot) systemctl reboot ;;
    Suspend) systemctl suspend ;;
    Hibernate) systemctl hibernate ;;
esac
