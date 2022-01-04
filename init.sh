#!/usr/bin/bash

# Using apt

sudo apt-get update
sudo apt-get install \
	i3 \
	i3-wm \
	dunst \
	i3lock \
	i3status \
	suckless-tools \
	compton \
	rxvt-unicode \
	xsel \
	rofi \
	feh \
	fonts-noto \
	fonts-mplus \
	xsettingsd \
	lxappearance \
	flameshot \
	gsimplecal \
	xclip \
	arc-theme

[[ -f ".bashrc" ]] && printf "\nsource .bashrc.custom" >>.bashrc
