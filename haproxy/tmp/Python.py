import requests
import socket
import time

# Thông tin backend và server tương ứng trong haproxy.cfg
servers = {
    "gateway1": "http://10.0.0.11:8080/metrics/active_users",
    "gateway2": "http://10.0.0.12:8080/metrics/active_users",
    "gateway3": "http://10.0.0.13:8080/metrics/active_users",
}

HAPROXY_SOCKET = "/var/run/haproxy.sock"
MAX_WEIGHT = 100

def get_active_users(url):
    try:
        r = requests.get(url, timeout=2)
        if r.status_code == 200:
            return int(r.text.strip())
    except Exception:
        pass
    return None

def set_weight(server_name, weight):
    cmd = f"set weight be_gateway/{server_name} {weight}\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(HAPROXY_SOCKET)
        s.sendall(cmd.encode())
        # optional: nhận response
        resp = s.recv(1024).decode()
        print(f"Set weight {server_name}={weight}, response: {resp.strip()}")

def main_loop():
    while True:
        weights = {}
        for srv, url in servers.items():
            active = get_active_users(url)
            if active is None:
                weight = 1  # server không trả lời → giảm ưu tiên
            else:
                # Đảo ngược active users thành weight (càng ít active càng ưu tiên)
                weight = MAX_WEIGHT - active
                if weight < 1:
                    weight = 1
            weights[srv] = weight

        print("Weights to set:", weights)
        for srv, w in weights.items():
            set_weight(srv, w)

        time.sleep(5)

if __name__ == "__main__":
    main_loop()
