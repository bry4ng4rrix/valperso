# Application web (Flutter) servie par nginx, qui transmet aussi /api, /media et /docs à l'API.
# Le dossier web/ est le résultat de `flutter build web`, ajouté par scripts/deploy.sh.
FROM nginx:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY web/ /usr/share/nginx/html/
