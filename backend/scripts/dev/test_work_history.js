const http = require("http");

const req = http.get("http://localhost:3000/api/workshop/work-history?branch_id=1", (res) => {
    let data = "";
    res.on("data", chunk => data += chunk);
    res.on("end", () => {
        try {
            const json = JSON.parse(data);
            console.log("Work history items count:", json.length);
            if (json.length > 0) {
                console.log("First item:", JSON.stringify(json[0], null, 2));
            }
        } catch (e) {
            console.log("Response:", data);
        }
    });
});

req.on("error", (e) => console.log("Error:", e.message));
