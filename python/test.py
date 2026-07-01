import webbrowser
import subprocess
import hashlib
import socket
import json
import time
import os

def get_file_hash(path :str, algo :str = 'sha256'):
    ctx = hashlib.new(algo)
    with open(path, 'rb') as f:
        while chunk := f.read(1 * 1024**2):
            ctx.update(chunk)
    return ctx.hexdigest()

def init_server_socket(
    bind_addr :str,
    bind_port :int,
    family    :int = socket.AF_INET,
    sock_type :int = socket.SOCK_STREAM,
    proto     :int = socket.IPPROTO_TCP,
    listen_n  :int = 5,
    ) -> socket.socket:
    fd = socket.socket(family, sock_type, proto)
    fd.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    fd.bind((bind_addr, bind_port))
    fd.listen(listen_n)
    return fd

def recv_all(fd : socket.socket):
    fd.settimeout(0.5)
    data = b''
    while True:
        try:
            tmp = fd.recv(4096)
        except:
            break
        data += tmp
    fd.settimeout(None)
    return data

def parse_client_data(data :bytes) -> dict:
    client_data_body_index = data.find(b'\r\n\r\n') + 4
    client_data_body = data[client_data_body_index:]
    client_data_body = client_data_body.decode()
    client_data_body = json.loads(client_data_body)
    return client_data_body

def json_stream(data :dict, print_json :bool = True, write_json :str = None) -> None:
    '''
    JSON 流处理，打印 / 写入文件

    Args:
        data (dict): 待处理的 dict 数据
        print_json (bool): 是否打印在终端
        write_json (str): 要保存的文件路径

    Returns:
        None
    '''
    def anonymization(data :dict):
        data['provider']['steamid'] = '1234567890123456'
        if data.get('player'):
            data['player']['steamid']   = '1234567890123456'
        return data

    if print_json:
        json_data = json.dumps(data, ensure_ascii=False, indent=4)
        print(f'[*] 获取客户端数据：\n{json_data}')

    if isinstance(write_json, (str)):
        with open(write_json, 'w', encoding='utf-8') as f:
            json_data = anonymization(data)
            json_data = json.dumps(json_data, ensure_ascii=False, indent=4)
            f.write(json_data)

def run(cmd :str):
    return subprocess.run(cmd, shell=True, stderr=subprocess.STDOUT, stdout=subprocess.PIPE).stdout.decode('gb18030')

def test(
    bind_addr :str = '127.0.0.1',
    bind_port :int = 23331,
    save_folder :str = 'test'
    ):
    server = init_server_socket(bind_addr, bind_port)

    os.makedirs(save_folder, exist_ok=True)

    print(f'[*] 绑定本地地址：[{bind_addr}:{bind_port}]，等待客户端连接。')
    seq = 1
    try:
        while True:
            client, c_addr = server.accept()
            print(f'[+] 客户端 {c_addr} 已连接。')

            client_data = parse_client_data(recv_all(client))
            client_data_save_path = os.path.join(save_folder, f'cs2_gsi_{seq:>04d}.json')

            json_stream(client_data, write_json=None)

            client.send((
                'HTTP/1.0 200 OK\r\n'
                'Server: SN_Server\r\n'
                '\r\n'
            ).encode())
            client.close()

            seq += 1
    except KeyboardInterrupt:
        print(f'[*] 退出服务器。')
        server.close()
    except Exception as e:
        print(f'[x] 出现致命错误！服务器无法继续！\n{e}')

def main():
    # 检查是否已经写入CFG文件，如果是，跳过。
    cfg_origin_path = 'gamestate_integration_cs2.cfg'
    cfg_save_path = 'G:/SteamLibrary/steamapps/common/Counter-Strike Global Offensive/game/csgo/cfg/gamestate_integration_cs2_die2play.cfg'
    cfg_content = None
    write_cfg = False

    with open(cfg_origin_path, 'r', encoding='utf-8') as f:
        cfg_content = f.read().split('---')[0].strip()

    if os.path.exists(cfg_save_path):
        if get_file_hash(cfg_origin_path) != get_file_hash(cfg_save_path):
            write_cfg = True
    else:
        write_cfg = True

    if write_cfg:
        print(f'[*] 检测到 CFG 未正确写入，将写入。')
        with open(cfg_save_path, 'w', encoding='utf-8') as f:
            f.write(cfg_content)

    # 如果重新写入了CFG文件
    if write_cfg:
        print(f'[*] 由于 CFG 文件已更新，需要重启一次游戏。')
        # 检查是否存在CS2进程，如果是，杀死并重启。
        res = run('tasklist | findstr /i cs2.exe').split()
        if res and (res[0] == 'cs2.exe'):
            print(f'[+] 检测到 CS2 进程[{res[1]}]，杀死。')
            run('taskkill /f /im cs2.exe')
        # 重启CS2进程（为了保证它会重新读CFG文件）
        webbrowser.open('steam://rungameid/730')

    test()

main()
