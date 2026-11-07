#!/usr/bin/env sh

test -z ${JDK_CERT_URLS} || echo ${JDK_CERT_URLS} | tr -s ',' '\n' | egrep '.+' | while read -r CERT_URL; do
  CERT_NAME=`basename ${CERT_URL}`;
  KEYSTORE='/etc/pki/ca-trust/extracted/java/cacerts';
  test ! -f /tmp/${CERT_NAME} && curl -k -o /tmp/${CERT_NAME} ${CERT_URL};
  keytool -import -alias ${CERT_NAME} -file /tmp/${CERT_NAME} -keystore ${KEYSTORE} -storepass changeit -noprompt &>/dev/null;
done

if [ -n "${OTEL_APP_NAME}" ]; then
    export JAVA_OPTS="${JAVA_OPTS} -javaagent:/opt/otel/libs/opentelemetry-javaagent.jar"
    export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-otlp}"
    export OTEL_METRICS_EXPORTER="${OTEL_METRICS_EXPORTER:-otlp}"
    export OTEL_EXPORTER_OTLP_PROTOCOL="${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}"
    export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://otel-collector:4317}"
    export OTEL_EXPORTER_OTLP_TIMEOUT="${OTEL_EXPORTER_OTLP_TIMEOUT:-10000}"
    export OTEL_EXPORTER_OTLP_INSECURE="${OTEL_EXPORTER_OTLP_INSECURE:-true}"
    export OTEL_JAVAAGENT_DEBUG="${OTEL_JAVAAGENT_DEBUG:-false}"
    export OTEL_RESOURCE_ATTRIBUTES="service.name=${OTEL_APP_NAME}"
    export OTEL_EXPORTER_OTEL_METRICS_HEADERS="namespace=${OTEL_APP_NAME}"
fi

exec gosu app "$@"
