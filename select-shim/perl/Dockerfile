FROM perl:5.38

RUN apt-get update && apt-get install -y \
    unixodbc unixodbc-dev \
    libmariadb-dev \
    curl \
 && curl -o /tmp/snowflake-odbc.deb \
    https://sfc-repo.snowflakecomputing.com/odbc/linux/3.5.0/snowflake-odbc-3.5.0.x86_64.deb \
 && dpkg -i /tmp/snowflake-odbc.deb \
 && rm /tmp/snowflake-odbc.deb \
 && ln -sf /usr/lib/x86_64-linux-gnu/libodbcinst.so.2 /usr/lib/x86_64-linux-gnu/libodbcinst.so.1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY cpanfile /app/cpanfile
RUN cpanm --notest --installdeps .

COPY shim.pl /app/shim.pl

CMD ["perl", "/app/shim.pl"]
