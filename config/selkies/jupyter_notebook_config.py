import os

c.ServerProxy.servers = {
    'desktop': {
        'command': ['/opt/neurodesktop/start_selkies.sh'],
        'port': 8082,
        'timeout': 120,
        'request_headers_override': {
            'Authorization': 'Basic am92eWFuOnBhc3N3b3Jk',
        },
        'launcher_entry': {
            'path_info': 'desktop',
            'title': 'Desktop (WebRTC)',
            'category': 'Neurodesk'
        }
    }
}

c.ServerApp.preferred_dir = os.getcwd()
c.FileContentsManager.allow_hidden = True
c.ServerApp.terminado_settings = {
    "shell_command": ["/bin/bash"]
}
