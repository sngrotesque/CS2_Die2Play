import webbrowser
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

def parse_client_data(data :bytes):
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
        data['player']['steamid']   = '1234567890123456'
        return data

    if print_json:
        json_data = json.dumps(data, ensure_ascii=False, indent=4)
        print(f'[*] 获取客户端数据：\n{json_data}')

    if isinstance(write_json, (bool)):
        print('[x] write_json 应是保存路径而不是布尔值。')
        return

    if isinstance(write_json, (str)):
        with open(write_json, 'w', encoding='utf-8') as f:
            json_data = anonymization(data)
            json_data = json.dumps(json_data, ensure_ascii=False, indent=4)
            f.wriet(json_data)

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

            json_stream(
                client_data, 
                write_json=os.path.join(save_folder, f'cs2_gsi_{seq:>04d}.json')
            )

            client.send((
                'HTTP/1.0 200 OK\r\n'
                'Server: SN_Server\r\n'
                '\r\n'
            ).encode())
            client.close()
    except KeyboardInterrupt:
        print(f'[*] 退出服务器。')
        server.close()
    except Exception as e:
        print(f'[x] 出现致命错误！服务器无法继续！\n{e}')

def main():
    cfg_path = r"G:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\gamestate_integration_cs2_die2play.cfg"
    cfg_content = None

    with open('gamestate_integration_cs2.cfg', 'r', encoding='utf-8') as f:
        cfg_content = f.read().split('---')[0]
    with open(cfg_path, 'w', encoding='utf-8') as f:
        f.write(cfg_content)

    test()

main()
