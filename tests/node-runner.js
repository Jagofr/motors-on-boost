// Shims for headless Node.js execution of Heaps JS target tests
if (typeof globalThis.window === 'undefined') {
    const headElem = { appendChild: () => {} };
    globalThis.window = globalThis;
    globalThis.document = {
        createElement: (tag) => ({
            setAttribute: () => {},
            appendChild: () => {},
            style: {}
        }),
        head: headElem,
        body: { appendChild: () => {} },
        getElementsByTagName: (tag) => [headElem],
        querySelector: () => null,
        querySelectorAll: () => []
    };
    globalThis.navigator = { userAgent: "Node" };
    globalThis.location = { href: "http://localhost/" };
    globalThis.localStorage = {
        _storage: {},
        getItem: function(k) { return this._storage[k] || null; },
        setItem: function(k, v) { this._storage[k] = String(v); },
        removeItem: function(k) { delete this._storage[k]; },
        clear: function() { this._storage = {}; }
    };
}

require('../bin/test.js');

