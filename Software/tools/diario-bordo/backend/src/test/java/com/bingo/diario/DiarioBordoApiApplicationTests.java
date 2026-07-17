package com.bingo.diario;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.boot.test.context.SpringBootTest.WebEnvironment.RANDOM_PORT;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpRequest.BodyPublisher;
import java.net.http.HttpRequest.BodyPublishers;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import com.bingo.diario.config.TimeConfig;

@SpringBootTest(webEnvironment = RANDOM_PORT)
@Import(DiarioBordoApiApplicationTests.FixedClockConfig.class)
class DiarioBordoApiApplicationTests {

    private static final String TEAM_PIN = "261026";
    private static final String ADMIN_PIN = "626262";
    private static final String AUTHORIZATION_HEADER = "Authorization";
    private static final String ADMIN_DATABASE_URL = "jdbc:postgresql://127.0.0.1:54324/postgres";
    private static final String DATABASE_URL = "jdbc:postgresql://127.0.0.1:54324/bingo_diario_test";
    private static final String DATABASE_USERNAME = "diario";
    private static final String DATABASE_PASSWORD = "diario_dev";
    private static final LocalDate TODAY = LocalDate.of(2026, 7, 14);

    static {
        initializeDatabaseSchema();
    }

    @LocalServerPort
    int port;

    HttpClient httpClient = HttpClient.newHttpClient();
    String teamToken;
    String adminToken;

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> DATABASE_URL);
        registry.add("spring.datasource.username", () -> DATABASE_USERNAME);
        registry.add("spring.datasource.password", () -> DATABASE_PASSWORD);
        registry.add("spring.flyway.enabled", () -> "false");
        registry.add("app.auth.team-pin", () -> TEAM_PIN);
        registry.add("app.auth.admin-pin", () -> ADMIN_PIN);
        registry.add("app.auth.signing-secret", () -> "integration-test-signing-secret-with-32-characters");
        registry.add("app.attachments.storage-path", () -> "target/test-uploads");
        registry.add("app.attachments.enabled", () -> "false");
    }

    @BeforeEach
    void resetData() throws Exception {
        try (Connection connection = DriverManager.getConnection(
                DATABASE_URL, DATABASE_USERNAME, DATABASE_PASSWORD);
             Statement statement = connection.createStatement()) {
            statement.execute("TRUNCATE diary_reports, diary_members RESTART IDENTITY CASCADE");
            statement.execute(readClasspath("test-seed.sql"));
        }
        teamToken = login("TEAM", TEAM_PIN);
        adminToken = login("ADMIN", ADMIN_PIN);
    }

    @Test
    void validatesTeamAndAdminPinsForSelectedRole() throws Exception {
        TestResponse teamResponse = post("/auth/access", Map.of("role", "TEAM", "pin", TEAM_PIN), null);
        TestResponse adminResponse = post("/auth/access", Map.of("role", "ADMIN", "pin", ADMIN_PIN), null);
        TestResponse wrongRoleResponse = post("/auth/access", Map.of("role", "ADMIN", "pin", TEAM_PIN), null);
        TestResponse invalidFormatResponse = post("/auth/access", Map.of("role", "TEAM", "pin", "2610"), null);

        assertThat(teamResponse.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(teamResponse.body())
                .contains("\"role\":\"TEAM\"")
                .contains("\"token\":")
                .contains("\"expiresAt\":");
        assertThat(adminResponse.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(adminResponse.body())
                .contains("\"role\":\"ADMIN\"")
                .contains("\"token\":")
                .contains("\"expiresAt\":");
        assertThat(wrongRoleResponse.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(invalidFormatResponse.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
    }

    @Test
    void requiresTeamPinToCreateReportsAndAdminPinToReadReports() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate yesterday = TODAY.minusDays(1);

        TestResponse unauthorizedCreate = post("/reports/today", validReport(memberId, yesterday), null);
        TestResponse unauthorizedRead = get("/reports", null);
        TestResponse authorizedCreate = post("/reports/today", validReport(memberId, yesterday), teamToken);
        TestResponse authorizedRead = get("/reports?date=" + yesterday, adminToken);

        assertThat(unauthorizedCreate.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(unauthorizedRead.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(authorizedCreate.status()).isEqualTo(HttpStatus.CREATED.value());
        assertThat(authorizedCreate.body()).contains("\"title\":\"Objetivo do dia\"");
        assertThat(authorizedCreate.body()).contains("\"decisions\":\"Decisão tomada\"");
        assertThat(authorizedCreate.body()).contains("\"reportDate\":\"" + yesterday + "\"");
        assertThat(authorizedCreate.body()).contains("\"status\":\"SUBMITTED_LATE\"");
        assertThat(authorizedRead.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(countObjects(authorizedRead.body())).isEqualTo(1);
    }

    @Test
    void protectsMemberDirectoryAndRejectsLegacyPinHeader() throws Exception {
        TestResponse withoutToken = get("/members", null);
        HttpRequest legacyRequest = HttpRequest.newBuilder(uri("/members"))
                .header("X-Diary-Password", TEAM_PIN)
                .GET()
                .build();
        TestResponse withLegacyPin = send(legacyRequest);
        TestResponse withToken = get("/members", teamToken);

        assertThat(withoutToken.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(withLegacyPin.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(withToken.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(withToken.body()).contains("Marco Caparra");
    }

    @Test
    void requiresExpandedDailyFieldsAndCalculatesTodayStatusAutomatically() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate today = TODAY;
        Map<String, Object> invalidReport = Map.of(
                "memberId", memberId,
                "reportDate", today.toString(),
                "area", "Software",
                "title", "Objetivo do dia",
                "description", "O que foi feito");

        TestResponse invalidResponse = post("/reports/today", invalidReport, teamToken);
        TestResponse validResponse = post("/reports/today", validReport(memberId, today), teamToken);

        assertThat(invalidResponse.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(validResponse.status()).isEqualTo(HttpStatus.CREATED.value());
        assertThat(validResponse.body()).contains("\"status\":\"SUBMITTED\"");
    }

    @Test
    void rejectsFutureReportDates() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate futureDate = TODAY.plusDays(1);

        TestResponse response = post("/reports/today", validReport(memberId, futureDate), teamToken);

        assertThat(response.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(response.body()).contains("datas futuras");
    }

    @Test
    void rejectsEvidenceAttachmentsWhenStorageIsDisabled() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate reportDate = TODAY;

        TestResponse created = multipartPostReport(
                "/reports/today",
                validReport(memberId, reportDate),
                "evidencia-teste.pdf",
                "application/pdf",
                "%PDF-1.4 diario de bordo".getBytes(StandardCharsets.UTF_8),
                teamToken);

        assertThat(created.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(created.body()).contains("Anexos").contains("desativados");
    }

    @Test
    void returnsPendingMembersForSelectedDate() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate reportDate = TODAY;
        post("/reports/today", validReport(memberId, reportDate), teamToken);

        TestResponse response = get("/reports/pending?date=" + reportDate, adminToken);

        assertThat(response.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(countObjects(response.body())).isEqualTo(4);
        assertThat(response.body())
                .contains("\"name\":\"Gustavo Bretas\"")
                .contains("\"name\":\"João Predeus\"");
    }

    @Test
    void letsTeamCheckWhetherMemberAlreadySubmittedForDate() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate reportDate = TODAY;
        post("/reports/today", validReport(memberId, reportDate), teamToken);

        TestResponse existingResponse = get("/reports/exists?memberId=" + memberId + "&date=" + reportDate, teamToken);
        TestResponse emptyResponse = get("/reports/exists?memberId=" + memberId + "&date=" + reportDate.minusDays(1), teamToken);

        assertThat(existingResponse.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(existingResponse.body())
                .contains("\"exists\":true")
                .contains("\"memberName\":\"Marco Caparra\"")
                .contains("\"reportDate\":\"" + reportDate + "\"");
        assertThat(emptyResponse.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(emptyResponse.body()).contains("\"exists\":false");
    }

    @Test
    void letsAdminUpdateReportContent() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate reportDate = TODAY;
        TestResponse created = post("/reports/today", validReport(memberId, reportDate), teamToken);
        UUID reportId = extractId(created.body());

        TestResponse updated = put("/reports/" + reportId, Map.ofEntries(
                Map.entry("area", "Gestão"),
                Map.entry("title", "Objetivo revisado"),
                Map.entry("description", "Descrição revisada"),
                Map.entry("participants", "Marco"),
                Map.entry("environment", "Online"),
                Map.entry("recordType", "Revisão"),
                Map.entry("decisions", "Decisão revisada"),
                Map.entry("testsAndObservations", "Observação revisada"),
                Map.entry("problems", "Sem riscos novos"),
                Map.entry("evidenceLinks", "Drive interno"),
                Map.entry("toolsUsed", "ChatGPT"),
                Map.entry("pendingItems", "Validar depois"),
                Map.entry("finalNotes", "Nota revisada")), adminToken);

        assertThat(updated.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(updated.body())
                .contains("\"title\":\"Objetivo revisado\"")
                .contains("\"decisions\":\"Decisão revisada\"")
                .contains("\"evidenceLinks\":\"Drive interno\"");
    }

    @Test
    void letsAdminDeleteReportAndReleaseMemberForSameDate() throws Exception {
        UUID memberId = memberIdByName("Marco Caparra");
        LocalDate reportDate = TODAY;
        TestResponse created = post("/reports/today", validReport(memberId, reportDate), teamToken);
        UUID reportId = extractId(created.body());

        TestResponse unauthorizedDelete = delete("/reports/" + reportId, null);
        TestResponse deleted = delete("/reports/" + reportId, adminToken);
        TestResponse existenceAfterDelete = get("/reports/exists?memberId=" + memberId + "&date=" + reportDate, teamToken);
        TestResponse recreated = post("/reports/today", validReport(memberId, reportDate), teamToken);

        assertThat(unauthorizedDelete.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(deleted.status()).isEqualTo(HttpStatus.NO_CONTENT.value());
        assertThat(existenceAfterDelete.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(existenceAfterDelete.body()).contains("\"exists\":false");
        assertThat(recreated.status()).isEqualTo(HttpStatus.CREATED.value());
    }

    @Test
    void allowsCorsPreflightForAdminReportUpdates() throws Exception {
        HttpRequest request = HttpRequest.newBuilder(uri("/reports/" + UUID.randomUUID()))
                .method("OPTIONS", HttpRequest.BodyPublishers.noBody())
                .header(HttpHeaders.ORIGIN, "http://127.0.0.1:5173")
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "PUT")
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "content-type,authorization")
                .build();

        TestResponse response = send(request);

        assertThat(response.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(response.header(HttpHeaders.ACCESS_CONTROL_ALLOW_METHODS.toLowerCase())).contains("PUT");
        assertThat(response.header(HttpHeaders.ACCESS_CONTROL_ALLOW_HEADERS.toLowerCase()).toLowerCase())
                .contains("authorization");
    }

    @Test
    void exportsSelectedDateAsMarkdownWithAnsweredNoActivityAndPendingSections() throws Exception {
        UUID firstMemberId = memberIdByName("Marco Caparra");
        UUID secondMemberId = memberIdByName("Gustavo Bretas");
        LocalDate reportDate = TODAY;
        post("/reports/today", validReport(firstMemberId, reportDate), teamToken);
        post("/reports/no-activity", Map.of(
                "memberId", secondMemberId,
                "reportDate", reportDate.toString()), teamToken);

        TestResponse response = get("/reports/export?date=" + reportDate, adminToken);

        assertThat(response.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(response.header("content-type")).contains(MediaType.valueOf("text/markdown;charset=UTF-8").toString());
        assertThat(response.header(HttpHeaders.CONTENT_DISPOSITION.toLowerCase()))
                .contains("diario-bordo-" + reportDate + ".md");
        assertThat(response.body())
                .contains("# Diário de Bordo — " + reportDate)
                .contains("## Registros enviados")
                .contains("### Marco Caparra")
                .contains("Objetivo do dia")
                .contains("Decisão tomada")
                .contains("## Próximo passo do Marco")
                .contains("## Sem atividade")
                .contains("Gustavo Bretas")
                .contains("selecionou que não trabalhou no projeto nesta data")
                .contains("## Pendentes");
    }

    private UUID memberIdByName(String name) throws Exception {
        TestResponse response = get("/members", teamToken);
        return extractMemberIdByName(response.body(), name);
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClockConfig {

        @Bean
        @Primary
        Clock fixedDiaryClock() {
            return Clock.fixed(Instant.parse("2026-07-14T15:00:00Z"), TimeConfig.DIARY_ZONE);
        }
    }

    private String login(String role, String pin) throws Exception {
        TestResponse response = post("/auth/access", Map.of("role", role, "pin", pin), null);
        if (response.status() != HttpStatus.OK.value()) {
            throw new IllegalStateException("Login failed: " + response.body());
        }
        return extractJsonString(response.body(), "token");
    }

    private Map<String, Object> validReport(UUID memberId, LocalDate reportDate) {
        return Map.ofEntries(
                Map.entry("memberId", memberId),
                Map.entry("reportDate", reportDate.toString()),
                Map.entry("area", "Software"),
                Map.entry("title", "Objetivo do dia"),
                Map.entry("description", "O que foi feito"),
                Map.entry("participants", "Marco e Predeus"),
                Map.entry("environment", "Online"),
                Map.entry("recordType", "Execução"),
                Map.entry("decisions", "Decisão tomada"),
                Map.entry("testsAndObservations", "Teste executado"),
                Map.entry("problems", "Risco observado"),
                Map.entry("evidenceLinks", "https://example.com/evidencia"),
                Map.entry("toolsUsed", "ChatGPT"),
                Map.entry("pendingItems", "Revisar com o time"),
                Map.entry("finalNotes", "Observação final"));
    }

    private static void initializeDatabaseSchema() {
        ensureTestDatabaseExists();
        try (Connection connection = DriverManager.getConnection(DATABASE_URL, DATABASE_USERNAME, DATABASE_PASSWORD);
             Statement statement = connection.createStatement()) {
            statement.execute("DROP TABLE IF EXISTS diary_report_attachments");
            statement.execute("DROP TABLE IF EXISTS diary_reports");
            statement.execute("DROP TABLE IF EXISTS diary_members");
            statement.execute("DROP TYPE IF EXISTS diary_report_status");
            statement.execute(readClasspath("test-schema.sql"));
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }

    private static void ensureTestDatabaseExists() {
        try (Connection connection = DriverManager.getConnection(ADMIN_DATABASE_URL, DATABASE_USERNAME, DATABASE_PASSWORD);
             Statement statement = connection.createStatement();
             ResultSet resultSet = statement.executeQuery("SELECT 1 FROM pg_database WHERE datname = 'bingo_diario_test'")) {
            if (!resultSet.next()) {
                statement.execute("CREATE DATABASE bingo_diario_test");
            }
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }

    private static String readClasspath(String path) throws Exception {
        return new String(new ClassPathResource(path).getInputStream().readAllBytes(), StandardCharsets.UTF_8);
    }

    private TestResponse get(String path, String token) throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri(path)).GET();
        if (token != null) {
            builder.header(AUTHORIZATION_HEADER, "Bearer " + token);
        }
        return send(builder.build());
    }

    private TestResponse post(String path, Object body, String token) throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri(path))
                .header(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .POST(HttpRequest.BodyPublishers.ofString(toJson(body), StandardCharsets.UTF_8));
        if (token != null) {
            builder.header(AUTHORIZATION_HEADER, "Bearer " + token);
        }
        return send(builder.build());
    }

    private TestResponse multipartPostReport(
            String path,
            Object reportBody,
            String filename,
            String contentType,
            byte[] fileContent,
            String token) throws Exception {
        String boundary = "----BinGoBoundary" + UUID.randomUUID();
        BodyPublisher bodyPublisher = BodyPublishers.ofByteArrays(List.of(
                ("--" + boundary + "\r\n"
                        + "Content-Disposition: form-data; name=\"report\"\r\n"
                        + "Content-Type: application/json\r\n\r\n"
                        + toJson(reportBody) + "\r\n"
                        + "--" + boundary + "\r\n"
                        + "Content-Disposition: form-data; name=\"files\"; filename=\"" + filename + "\"\r\n"
                        + "Content-Type: " + contentType + "\r\n\r\n").getBytes(StandardCharsets.UTF_8),
                fileContent,
                ("\r\n--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8)
        ));
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri(path))
                .header(HttpHeaders.CONTENT_TYPE, "multipart/form-data; boundary=" + boundary)
                .POST(bodyPublisher);
        if (token != null) {
            builder.header(AUTHORIZATION_HEADER, "Bearer " + token);
        }
        return send(builder.build());
    }

    private TestResponse put(String path, Object body, String token) throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri(path))
                .header(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .PUT(HttpRequest.BodyPublishers.ofString(toJson(body), StandardCharsets.UTF_8));
        if (token != null) {
            builder.header(AUTHORIZATION_HEADER, "Bearer " + token);
        }
        return send(builder.build());
    }

    private TestResponse delete(String path, String token) throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri(path))
                .DELETE();
        if (token != null) {
            builder.header(AUTHORIZATION_HEADER, "Bearer " + token);
        }
        return send(builder.build());
    }

    private URI uri(String path) {
        return URI.create("http://127.0.0.1:" + port + path);
    }

    private TestResponse send(HttpRequest request) throws Exception {
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        return new TestResponse(response.statusCode(), response.headers().map(), response.body());
    }

    record TestResponse(int status, Map<String, List<String>> headers, String body) {
        String header(String name) {
            return headers.getOrDefault(name, List.of()).stream().findFirst().orElse("");
        }
    }

    private UUID extractMemberIdByName(String body, String name) {
        Matcher matcher = Pattern.compile("\\{[^}]*\"id\"\\s*:\\s*\"([^\"]+)\"[^}]*\"name\"\\s*:\\s*\"" + Pattern.quote(name) + "\"[^}]*}").matcher(body);
        if (!matcher.find()) {
            throw new IllegalStateException("Member id not found for " + name + " in response: " + body);
        }
        return UUID.fromString(matcher.group(1));
    }

    private UUID extractId(String body) {
        Matcher matcher = Pattern.compile("\"id\"\\s*:\\s*\"([^\"]+)\"").matcher(body);
        if (!matcher.find()) {
            throw new IllegalStateException("Id not found in response: " + body);
        }
        return UUID.fromString(matcher.group(1));
    }

    private String extractJsonString(String body, String propertyName) {
        Matcher matcher = Pattern.compile("\"" + Pattern.quote(propertyName) + "\"\\s*:\\s*\"([^\"]+)\"").matcher(body);
        if (!matcher.find()) {
            throw new IllegalStateException(propertyName + " not found in response: " + body);
        }
        return matcher.group(1);
    }

    private int countObjects(String jsonArray) {
        Matcher matcher = Pattern.compile("\\{").matcher(jsonArray);
        int count = 0;
        while (matcher.find()) {
            count++;
        }
        return count;
    }

    private String toJson(Object body) {
        if (body instanceof Map<?, ?> map) {
            return map.entrySet()
                    .stream()
                    .map(entry -> "\"" + escape(entry.getKey().toString()) + "\":" + jsonValue(entry.getValue()))
                    .reduce("{", (current, item) -> current.equals("{") ? current + item : current + "," + item)
                    + "}";
        }
        throw new IllegalArgumentException("Unsupported body type: " + body.getClass());
    }

    private String jsonValue(Object value) {
        if (value instanceof UUID uuid) {
            return "\"" + uuid + "\"";
        }
        if (value instanceof Number number) {
            return number.toString();
        }
        return "\"" + escape(value.toString()) + "\"";
    }

    private String escape(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
