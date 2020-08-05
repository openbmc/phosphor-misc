redirect = dependency('systemd', required: get_option('http-redirect'))


if redirect.found()
    install_data(
        'http-redirect.awk',
        install_mode: 'rwxr-xr-x',
        install_dir: get_option('bindir'),
    )

    unit_files = [
        'http-redirect.socket',
        'http-redirect@.service'
    ]

    foreach unit : unit_files
        configure_file(
            input: unit,
            output: unit,
            copy: true,
            install_dir:
                redirect.get_pkgconfig_variable('systemdsystemunitdir'),
        )
    endforeach
endif
