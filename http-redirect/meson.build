redirect = dependency('systemd', required: get_option('http-redirect'))


if redirect.found()
    install_data(
        'http-redirect.awk',
        install_mode: 'rwxr-xr-x',
        install_dir: get_option('bindir'),
    )

    configure_file(
        input: 'http-redirect.socket',
        output: 'http-redirct.socket',
        copy: true,
        install_dir:
            redirect.get_pkgconfig_variable('systemdsystemunitdir'),
    )
    configure_file(
        input: 'http-redirect@.service',
        output: 'http-redirct@.service',
        copy: true,
        install_dir:
            redirect.get_pkgconfig_variable('systemdsystemunitdir'),
    )
endif
