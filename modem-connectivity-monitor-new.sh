#!/bin/bash
# More to be considered
# 1. We read ip address of gateway from route list which may get outdated

get_gateway() {
    local interface=$1
    ip route list | awk -v iface="$interface" '$1 == "default" && $2 == "via"  && $0 ~ iface {print $3; exit}'
}

get_routes() {
    local interface=$1
    local metric=$2
    ip route list | awk -v iface="$interface" -v metric="$metric" '$1 == "default" && $0 ~ iface && $0 ~ "metric " metric {print}'
}

add_route() {
    local gateway=$1
    local interface=$2
    local metric=$3
    route add default gw $gateway dev $interface metric $metric
}

delete_route() {
    local interface=$1
    local metric=$2
    ip route del default dev $interface metric $metric
}

check_unexpected_routes() {
  low_metric=$1
  high_metric=$2
  ip route list | awk '$1 == "default" {print}' |
  while read line; do
  if [[ ! $line =~ metric ]]; then
    echo "Warning: found unexpected routes: $line"
    if [[ $line =~ wan ]]; then
      interface=$(echo $line | awk -F 'dev ' '{print $2}' | awk '{print $1}')
      delete_route $interface 0
      echo "delete no metric routes: $line"
    fi
  elif [[ $line =~ $low_metric || $line =~ $high_metric ]]; then
    :
  else
    echo "Warning: found unexpected routes: $line"
  fi
  done
}


LOW_METRIC=100
HIGH_METRIC=500
CHECK_IP="8.8.8.8"

INTERFACES=$(ip link show | awk -F: '$0 ~ "ww.*_1|enx.*"{print $2;getline}')

for INTERFACE in $INTERFACES
do
  IP_CHECK_PASSED=false

  if ping -I $INTERFACE -c 4 -W 1 $CHECK_IP > /dev/null
  then
    IP_CHECK_PASSED=true
  fi

  if $IP_CHECK_PASSED
  then
    ALL_LOW_METRIC_ROUTES=$(get_routes "" $LOW_METRIC)
    if [[ -n $ALL_LOW_METRIC_ROUTES ]]
    then
      continue
    fi
    GATEWAY=$(get_gateway $INTERFACE)  #TODO: we should get gateway in a better way, to get the realtime gateway
    if [ -z "$GATEWAY" ]; then
      echo "Warning: Get gateway failed for interface $INTERFACE"
      continue
    fi
    add_route $GATEWAY $INTERFACE $LOW_METRIC
    while [[ -n $(get_routes $INTERFACE $HIGH_METRIC) ]]; do
      delete_route $INTERFACE $HIGH_METRIC
    done
  else
    HIGH_METRIC_ROUTES=$(get_routes $INTERFACE $HIGH_METRIC)
    if [[ -z "$HIGH_METRIC_ROUTES" ]]
    then
      GATEWAY=$(get_gateway $INTERFACE)
      if [ -z "$GATEWAY" ]; then
        echo "Warning: Get gateway failed for interface $INTERFACE"
        continue
      fi
      add_route $GATEWAY $INTERFACE $HIGH_METRIC
    fi
    while [[ -n $(get_routes $INTERFACE $LOW_METRIC) ]]; do
      delete_route $INTERFACE $LOW_METRIC
    done
  fi
done

check_unexpected_routes $LOW_METRIC $HIGH_METRIC

