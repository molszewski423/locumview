/* LocumView branding: replace Guacamole's favicons with the LocumView app icon. */
(function () {
    var base = 'app/ext/locumview-branding/images/';
    var links = document.querySelectorAll('link[rel="icon"], link[rel="apple-touch-icon"]');
    for (var i = 0; i < links.length; i++) {
        var big = links[i].getAttribute('sizes') || links[i].rel === 'apple-touch-icon';
        links[i].setAttribute('href', base + (big ? 'locumview-icon-192.png' : 'locumview-icon-32.png'));
    }
})();
