FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /workspace
COPY backend/.mvn backend/.mvn
COPY backend/mvnw backend/pom.xml backend/
COPY database database
RUN chmod +x backend/mvnw && cd backend && ./mvnw -B -DskipTests dependency:go-offline

COPY backend/src backend/src
RUN cd backend && ./mvnw -B -DskipTests package

FROM eclipse-temurin:21-jre-alpine

RUN addgroup -S bingo && adduser -S bingo -G bingo
WORKDIR /app
COPY --from=build /workspace/backend/target/app.jar /app/app.jar

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:+UseSerialGC -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/urandom"

USER bingo
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar", "--spring.profiles.active=prod"]
