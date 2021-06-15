#!/bin/bash

# simple script to cleanup resources that may have been started/created by run.sh
sudo umount -l /btrfs
rm -f ~/disk.img
sudo systemctl stop docker &> /dev/null
sudo ip netns delete "netns1" || echo ""
sudo ip link delete hnetns1 || echo ""
sudo iptables -D FORWARD -o eth0 -i hnetns1 -j ACCEPT || echo ""
sudo iptables -D FORWARD -i eth0 -o hnetns1 -j ACCEPT || echo ""
sudo iptables -t nat -D POSTROUTING -s 192.168.100.0/24 -o eth0 -j MASQUERADE || echo ""
