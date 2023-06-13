#!/usr/bin/env sh

ONT_IF="igb5"
EAP_SUPPLICANT_IDENTITY="XX:XX:XX:XX:XX:XX"
LOG=/var/log/pfatt.log

getTimestamp(){
    echo `date "+%Y-%m-%d %H:%M:%S :: [pfatt_reddit.sh] ::"`
}

##### DO NOT EDIT BELOW #################################################################################
/usr/bin/logger -st "pfatt" "starting pfatt..."
/usr/bin/logger -st "pfatt" "configuration:"
/usr/bin/logger -st "pfatt" "  ONT_IF = $ONT_IF"
/usr/bin/logger -st "pfatt" "  EAP_SUPPLICANT_IDENTITY = $EAP_SUPPLICANT_IDENTITY"
/usr/bin/logger -st "pfatt" "your ONT should be connected to pyshical interface $ONT_IF"

/sbin/ifconfig $ONT_IF down
/sbin/ifconfig $ONT_IF ether $EAP_SUPPLICANT_IDENTITY
/sbin/ifconfig $ONT_IF up

/usr/bin/logger -st "pfatt" "starting wpa_supplicant..."

WPA_PARAMS="\
  set eapol_version 2,\
  set fast_reauth 1,\
  ap_scan 0,\
  add_network,\
  set_network 0 ca_cert \\\"/root/pfatt/wpa/ca.pem\\\",\
  set_network 0 client_cert \\\"/root/pfatt/wpa/client.pem\\\",\
  set_network 0 eap TLS,\
  set_network 0 eapol_flags 0,\
  set_network 0 identity \\\"$EAP_SUPPLICANT_IDENTITY\\\",\
  set_network 0 key_mgmt IEEE8021X,\
  set_network 0 phase1 \\\"allow_canned_success=1\\\",\
  set_network 0 private_key \\\"/root/pfatt/wpa/private.pem\\\",\
  enable_network 0\
"
#Placeholder wpa_supplicant location
WPA_DAEMON_CMD="/root/wpa_supplicant -Dwired -i$ONT_IF -B -C /var/run/wpa_supplicant"

# Kill any existing wpa_supplicant process.
PID=$(pgrep -f "wpa_supplicant")
if [ ${PID} > 0 ];
then
	/usr/bin/logger -st "pfatt" "terminating existing wpa_supplicant on PID ${PID}..."
	RES=$(kill ${PID})
fi

# Start wpa_supplicant daemon.
RES=$(${WPA_DAEMON_CMD})
PID=$(pgrep -f "wpa_supplicant")
/usr/bin/logger -st "pfatt" "wpa_supplicant running on PID ${PID}..."

# Set WPA configuration parameters.
/usr/bin/logger -st "pfatt" "setting wpa_supplicant network configuration..."
IFS=","
for STR in ${WPA_PARAMS};
do
	STR="$(echo -e "${STR}" | sed -e 's/^[[:space:]]*//')"
	RES=$(eval wpa_cli ${STR})
done

# Create variables to check authentication status.
WPA_STATUS_CMD="wpa_cli status | grep 'suppPortStatus' | cut -d= -f2"
IP_STATUS_CMD="ifconfig $ONT_IF | grep 'inet\ ' | cut -d' ' -f2"
/usr/bin/logger -st "pfatt" "waiting for EAP authorization..."

# Check authentication once per 5 seconds for 25 seconds (5 attempts).
i=1
until [ "$i" -eq "5" ]
do
	sleep 5
	WPA_STATUS=$(eval ${WPA_STATUS_CMD})
	if [ X${WPA_STATUS} = X"Authorized" ];
	then
		/usr/bin/logger -st "pfatt" "EAP authorization completed..."

		IP_STATUS=$(eval ${IP_STATUS_CMD})

		if [ -z ${IP_STATUS} ] || [ ${IP_STATUS} = "0.0.0.0" ];
		then
			/usr/bin/logger -st "pfatt" "no IP address assigned, force restarting DHCP..."
			RES=$(eval /etc/rc.d/dhclient forcerestart $ONT_IF)
			IP_STATUS=$(eval ${IP_STATUS_CMD})
		fi
		/usr/bin/logger -st "pfatt" "IP address is ${IP_STATUS}..."
		/usr/bin/logger -st "pfatt" "$ONT_IF should now be available to configure as your WAN..."
		sleep 5
		break
	else
		/usr/bin/logger -st "pfatt" "no authentication, retrying ${i}/5..."
		i=$((i+1))
	fi
done