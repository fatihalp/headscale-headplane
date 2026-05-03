FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /workspace
COPY . /workspace
COPY install.sh /opt/install.sh
RUN chmod +x /opt/install.sh

EXPOSE 80
CMD ["sleep", "infinity"]