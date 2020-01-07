set_mac = dependency('systemd', required: get_option('first-boot-set-mac'))
set_hostname = dependency('systemd', required: get_option('first-boot-set-hostname'))

if set_mac.found()
    install_data(
        'first-boot-set-mac.sh',
        install_mode: 'rwxr-xr-x',
        install_dir: get_option('bindir'),
    )

    configure_file(
        input: 'first-boot-set-mac@.service',
        output: 'first-boot-set-mac@.service',
        copy: true,
        install_dir:
            set_mac.get_pkgconfig_variable('systemdsystemunitdir'),
    )
endif

if set_hostname.found()
    install_data(
        'first-boot-set-hostname.sh',
        install_mode: 'rwxr-xr-x',
        install_dir: get_option('bindir'),
    )

    configure_file(
        input: 'first-boot-set-hostname.service',
        output: 'first-boot-set-hostname.service',
        copy: true,
        install_dir:
            set_hostname.get_pkgconfig_variable('systemdsystemunitdir'),
    )
endif
