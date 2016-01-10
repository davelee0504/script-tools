#!/bin/ksh

##############################################################################
## original from http://seriousbirder.com/blogs/centos-and-red-hat-enterprise-sample-iptables-script/
## slightly modified to meet my needs
##############################################################################

##############################################################################
### iptables firewall shell script
##############################################################################
 
ipt="/sbin/iptables"
spammers="blockedip"
message="dropped ip"
 
##############################################################################
### sysctl net.ipv4 settings
##############################################################################
 echo "net.ipv4 tuneables"
 sysctl net.ipv4.conf.all.rp_filter=1
 sysctl net.ipv4.conf.default.rp_filter=1
 sysctl net.ipv4.conf.all.accept_source_route=0
 sysctl net.ipv4.conf.all.send_redirects=0
 sysctl net.ipv4.conf.default.send_redirects=0
 sysctl net.ipv4.conf.all.accept_redirects=0
 sysctl net.ipv4.conf.all.secure_redirects=0
 sysctl net.ipv4.conf.all.log_martians=1   # to log spoofed and source routed and redirects
 sysctl net.ipv4.ip_forward=1  # think this is the default anyways
 sysctl net.ipv4.conf.default.accept_source_route=0
 sysctl net.ipv4.conf.default.accept_redirects=0
 sysctl net.ipv4.conf.default.secure_redirects=0
 sysctl net.ipv4.tcp_syncookies=1
 sysctl kernel.exec-shield=1
 sysctl kernel.randomize_va_space=1
 echo "done net.ipv4"
 
######################################################################################################
### My system has eth0 set on an internal service / data / monitoring network.
### eth1 is connnected to the dark and evil side, and it the interface that needs all the rules. So I
### will  only allow ssh from this interface. See my ssh rule below. I haven't yet (because of lazyness)
### implemented too many rules on the service network.
######################################################################################################
 
echo "Starting filtering rules"
### Start by deleting every non-builtin chain in the iptable. This is good housekeeping.
$ipt -X
# Start and flush the firewall / packet filtering tables. This is good housekeeping too!
$ipt -F
 
# load kernel module
modprobe ip_conntrack
 
# some people feel the need to open up the loopback. Might as well.
$ipt -A INPUT -i lo -j ACCEPT
$ipt -A OUTPUT -o lo -j ACCEPT
 
# DROP all incomming traffic
$ipt -P INPUT DROP
$ipt -P OUTPUT DROP
$ipt -P FORWARD DROP
 
###############################################################
### quick and dirty IP's to block table. If it's there and it
### has some unfriendly IP's, then create a chain name and
### add a rule to block and log the attempts.
###############################################################
 
if [ ! -s /etc/evil_ip_list ]; then
   echo "no IP's to block"
 else
   $ipt -N $spammers # create a new iptables chain name
 
 for bad_ip in $(cat /etc/evil_ip_list); do
   $ipt -A $spammers -s $bad_ip -j LOG --log-prefix "$message "
   $ipt -A $spammers -s $bad_ip -j DROP
 done
   ### solidify the chain name
   $ipt -I INPUT -j $spammers
   $ipt -I OUTPUT -j $spammers
   $ipt -I FORWARD -j $spammers
fi
 
###############################################################
### First and foremost, allow ssh ONLY from our service network
### which is on eth1, not eth0. This is my only rule for eth1
### right now. Have to fix this later on.
###############################################################
 
#$ipt -A INPUT -i eth1 -p tcp --destination-port 22 -j ACCEPT
$ipt -A INPUT -i eth0 -p tcp --destination-port 22 -j ACCEPT
 
###############################################################
### Open up our web ports, this is a web server
###############################################################
 
$ipt -A INPUT -i eth0 -p tcp --destination-port 80 -j ACCEPT
$ipt -A INPUT -i eth0 -p tcp --destination-port 443 -j ACCEPT
 
###############################################################
### Open up for pptpd service
###############################################################

$ipt -A INPUT -p tcp -m tcp --dport 1723 -j ACCEPT
$ipt -A INPUT -p gre -j ACCEPT
$ipt -t nat -A POSTROUTING -s 192.168.240.0/24 -o eth0 -j MASQUERADE
 
###############################################################
### drop the scan type packets. No need for that type of behaviour
###############################################################
 
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags FIN,ACK FIN -m limit --limit 10/m --limit-burst 8 -j LOG --log-level 4 --log-prefix "FIN Packet Scan"
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags FIN,ACK FIN -j DROP
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
 
###############################################################
### general blocks
###############################################################
 
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags ALL ALL -j DROP
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags ALL NONE -j DROP # drop NULL packets
 
###############################################################
### The infamous (but rare I think) Xmas packet is a sort of out-of-state FIN or ACK packet.
### I believe these packets have every single option set for whatever protocol it
### uses and can pass through. Lets drop the bastards.
###############################################################
 
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags SYN,FIN SYN,FIN -m limit --limit 10/m --limit-burst 8 -j LOG --log-level 4 --log-prefix "XMAS Packets"
$ipt  -A INPUT -i eth0 -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
 
###############################################################
### Block some sync and fragmented packets
###############################################################
 
$ipt -A INPUT -i eth0 -p tcp ! --syn -m state --state NEW  -m limit --limit 5/m --limit-burst 7 -j LOG --log-level 4 --log-prefix "Drop Sync" # not sure this works yet. test me.
$ipt -A INPUT -i eth0 -p tcp ! --syn -m state --state NEW -j DROP
$ipt -A INPUT -i eth0 -f  -m limit --limit 10/m --limit-burst 7 -j LOG --log-level 4 --log-prefix "Fragmented Packets"
$ipt -A INPUT -i eth0 -f -j DROP
 
###############################################################
### Allow full outgoing connection but no incomming stuff
###############################################################
 
$ipt -A INPUT -i eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT
$ipt -A OUTPUT -o eth0 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
 
###############################################################
### We want to see / analyze and record traffic.
### So lets DROP the bad stuff and log it
###############################################################
 
$ipt -A INPUT -j LOG
$ipt -A FORWARD -j LOG
$ipt -A INPUT -j DROP
 
echo "done packet filtering setup, you are now safe\!"