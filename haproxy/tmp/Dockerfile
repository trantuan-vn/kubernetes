FROM haproxy:2.8
RUN apt update && apt install -y python3 curl
COPY loadagent.py /usr/local/bin/
CMD ["/usr/local/bin/loadagent.py"]
