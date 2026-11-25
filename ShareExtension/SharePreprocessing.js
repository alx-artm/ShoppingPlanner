// SharePreprocessing.js
// ShareExtension
//
// Safari runs this in the shared page before the extension opens and hands the result to
// the extension (NSExtensionJavaScriptPreprocessingFile, spec 06 B.4 p.4). It only
// collects strings: every choice (title, price, currency, picture) is made in Swift
// (`SharePage`, `SharePrice`), where unit tests cover it. Keys: `SharePage.Key`.

var SharePreprocessing = function() {};

SharePreprocessing.prototype = {
    run: function(arguments) {
        var maxBlocks = 5;            // SharePage.maxJSONLDBlocks
        var maxBlockLength = 51200;   // SharePage.maxJSONLDLength (50 KB)
        var maxValues = 5;            // SharePage.maxMetaValues

        function metaValues(name) {
            var values = [];
            var nodes = document.querySelectorAll('meta[property="' + name + '"], meta[name="' + name + '"]');
            for (var i = 0; i < nodes.length && values.length < maxValues; i++) {
                var content = nodes[i].getAttribute('content');
                if (content) { values.push(content); }
            }
            return values;
        }

        function first(name) {
            var values = metaValues(name);
            return values.length > 0 ? values[0] : '';
        }

        function absolute(link) {
            if (!link) { return ''; }
            try { return new URL(link, document.baseURI).href; } catch (e) { return ''; }
        }

        var canonical = document.querySelector('link[rel="canonical"]');
        var jsonLD = [];
        var scripts = document.querySelectorAll('script[type="application/ld+json"]');
        for (var i = 0; i < scripts.length && jsonLD.length < maxBlocks; i++) {
            var text = scripts[i].textContent || '';
            if (text.length > 0 && text.length <= maxBlockLength) { jsonLD.push(text); }
        }

        arguments.completionFunction({
            url: document.URL,
            title: document.title || '',
            ogTitle: first('og:title'),
            ogImage: absolute(first('og:image')),
            ogImageSecure: absolute(first('og:image:secure_url')),
            canonical: canonical ? absolute(canonical.getAttribute('href')) : '',
            productPriceAmount: metaValues('product:price:amount'),
            productPriceCurrency: metaValues('product:price:currency'),
            ogPriceAmount: metaValues('og:price:amount'),
            ogPriceCurrency: metaValues('og:price:currency'),
            jsonLD: jsonLD
        });
    }
};

var ExtensionPreprocessingJS = new SharePreprocessing;
