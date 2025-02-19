FROM apache/hadoop:3

RUN curl -o /tmp/spark-3.5.4-bin-hadoop3.tgz -q https://dlcdn.apache.org/spark/spark-3.5.4/spark-3.5.4-bin-hadoop3.tgz \
	&& tar xfz /tmp/spark-3.5.4-bin-hadoop3.tgz -C /tmp \
	&& mv /tmp/spark-3.5.4-bin-hadoop3 /opt/spark \
	&& rm /tmp/spark-3.5.4-bin-hadoop3.tgz

ENV SPARK_HOME=/opt/spark
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin
ENV LD_LIBRARY_PATH=/opt/hadoop/lib/native

