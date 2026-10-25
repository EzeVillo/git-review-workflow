/* Custom events supplement the Umami tracker configured in the page heads.
   Link events use Umami's data attributes; these two events need a success signal. */
(function () {
    "use strict";

    function track(name, properties) {
        try {
            if (window.umami && typeof window.umami.track === "function") {
                var result = window.umami.track(name, properties);
                if (result && typeof result.catch === "function") {
                    result.catch(function () { /* A collector may be offline. */ });
                }
            }
        } catch (error) { /* Analytics must never interrupt the page. */ }
    }

    var methods = ["npm", "homebrew", "powershell", "shell"];
    document.addEventListener("gitreview:command-copied", function (event) {
        var button = event.target;
        var method = button.getAttribute && button.getAttribute("data-install-method");
        if (methods.indexOf(method) !== -1) {
            track("install_command_copy", {method: method});
        }
    });

    var film = document.getElementById("ide-film");
    if (!film) return;
    var played = {};
    film.addEventListener("play", function () {
        var selected = document.querySelector('[data-demo-client][aria-pressed="true"]');
        var client = selected && selected.getAttribute("data-demo-client");
        if (["vscode", "jetbrains", "visualstudio"].indexOf(client) === -1 || played[client]) return;
        played[client] = true;
        track("demo_play", {interface: client});
    });
})();
