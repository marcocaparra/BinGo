export function apiBaseUrl() {
    const { hostname } = window.location;

    if (hostname.endsWith('.github.dev')) {
        const newHostname = hostname.replace('5173', '8000');
        return `https://${newHostname}`;
    }

    return "http://localhost:8000";
}

export const STORAGE_KEYS = {
    token: "access_token",
    user: "current_user",
};