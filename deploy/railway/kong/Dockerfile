FROM kong:2.8.1

# Rendered at container startup with environment-variable interpolation.
COPY kong.railway.yml /home/kong/temp.yml

ENV KONG_DATABASE=off
ENV KONG_DECLARATIVE_CONFIG=/home/kong/kong.yml
ENV KONG_DNS_ORDER=LAST,A,CNAME

ENTRYPOINT ["bash", "-c", "export KONG_PROXY_LISTEN=\"0.0.0.0:${PORT:-8000}\" && content=\"$(cat ~/temp.yml)\" && content=\"${content//'${AUTH_UPSTREAM}'/${AUTH_UPSTREAM}}\" && content=\"${content//'${REST_UPSTREAM}'/${REST_UPSTREAM}}\" && content=\"${content//'${STORAGE_UPSTREAM}'/${STORAGE_UPSTREAM}}\" && content=\"${content//'${REALTIME_UPSTREAM}'/${REALTIME_UPSTREAM}}\" && content=\"${content//'${SUPABASE_ANON_KEY}'/${SUPABASE_ANON_KEY}}\" && content=\"${content//'${SUPABASE_SERVICE_KEY}'/${SUPABASE_SERVICE_KEY}}\" && printf '%s\\n' \"$content\" > ~/kong.yml && /docker-entrypoint.sh kong docker-start"]
