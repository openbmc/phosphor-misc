#!/bin/bash -eu

function show_error() {
    if [ -n "${JOURNAL_STREAM-}" ]; then
        echo "$@" | systemd-cat -t first-boot-set-hostname -p emerg
    else
        echo "$@" >&2
    fi
}

function sync_hostname() {
    MAPPER_IFACE='xyz.openbmc_project.ObjectMapper'
    MAPPER_PATH='/xyz/openbmc_project/object_mapper'
    INVENTORY_PATH='/xyz/openbmc_project/inventory'

    BMC_ITEM_IFACE='xyz.openbmc_project.Inventory.Item.Bmc'
    INV_ASSET_IFACE='xyz.openbmc_project.Inventory.Decorator.Asset'
    BMC_SN=''
    BMC_ITEM_PATH=$(busctl --no-pager --verbose call \
            ${MAPPER_IFACE} ${MAPPER_PATH} ${MAPPER_IFACE} \
            GetSubTree sias \
            ${INVENTORY_PATH} 0 1 ${BMC_ITEM_IFACE} \
        2>/dev/null | grep ${INVENTORY_PATH} || true)

    # '     STRING "/xyz/openbmc_project/inventory/system/chassis/bmc";'
    BMC_ITEM_PATH=${BMC_ITEM_PATH#*\"}
    BMC_ITEM_PATH=${BMC_ITEM_PATH%\"*}

    BMC_ITEM_SERVICE=$(mapper get-service \
        "${BMC_ITEM_PATH}" 2>/dev/null || true)

    if [[ -n "${BMC_ITEM_SERVICE}" && -n "${BMC_ITEM_PATH}" ]]; then
        BMC_SN=$(busctl get-property "${BMC_ITEM_SERVICE}" \
            "${BMC_ITEM_PATH}" "${INV_ASSET_IFACE}" SerialNumber)
        # 's "002B0DH1000"'
        BMC_SN=${BMC_SN#*\"}
        BMC_SN=${BMC_SN%\"*}
    else
        show_error "No BMC item found in the Inventory. Is VPD EEPROM empty?"
    fi

    if [[ -z "${BMC_SN}" ]] ; then
        show_error "BMC Serial Number empty! Setting Hostname as 'hostname + mac address' "

        MAC_ADDR=''
        NETWORK_ITEM_IFACE='xyz.openbmc_project.Inventory.Item.NetworkInterface'
        NETWORK_ITEM_PATH=$(busctl --no-pager --verbose call \
                ${MAPPER_IFACE} ${MAPPER_PATH} ${MAPPER_IFACE} \
                GetSubTree sias \
                ${INVENTORY_PATH} 0 1 ${NETWORK_ITEM_IFACE} \
            2>/dev/null | grep ${INVENTORY_PATH} || true)

        NETWORK_ITEM_PATH=${NETWORK_ITEM_PATH#*\"}
        NETWORK_ITEM_PATH=${NETWORK_ITEM_PATH%\"*}

        NETWORK_ITEM_OBJ=$(mapper get-service "${NETWORK_ITEM_PATH}" 2>/dev/null || true)

        if [[ -n "${NETWORK_ITEM_OBJ}" && -n "${NETWORK_ITEM_PATH}" ]]; then
            MAC_ADDR=$(busctl get-property "${NETWORK_ITEM_OBJ}" \
                "${NETWORK_ITEM_PATH}" "${NETWORK_ITEM_IFACE}" MACAddress)
            # 's "54:52:01:02:03:04"'
            MAC_ADDR=${MAC_ADDR#*\"}
            MAC_ADDR=${MAC_ADDR%\"*}
        else
            show_error 'No Ethernet interface found in the Inventory.'
        fi

        if [[ -z "${MAC_ADDR}" ]] ; then
            show_error "Ethernet interface inventory empty! Setting Hostname as 'hostname + env mac address' "
            MAC_ADDR=$(fw_printenv ethaddr 2>/dev/null || true)
            MAC_ADDR=${MAC_ADDR#*=}
        fi

        if [ -z "${MAC_ADDR}" ]; then
            show_error 'No ethaddr found in the U-Boot env. Unique hostname not set!'
            exit 1
        fi

        hostnamectl set-hostname "$(hostname)-${MAC_ADDR}"
    else
        hostnamectl set-hostname "$(hostname)-${BMC_SN}"
    fi
}

sync_hostname

# Prevent start at next boot time
touch "/var/lib/first-boot-set-hostname"
