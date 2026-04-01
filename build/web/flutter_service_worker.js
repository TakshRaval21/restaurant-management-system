'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "be91d359e0d0ecdd2fac71de8c850e6e",
"assets/AssetManifest.bin.json": "48da1fe81e4b620d46517b4f00e38ab4",
"assets/assets/images/Brownie%2520with%2520Ice%2520Cream.jpg": "532b7568bcf10a53c0960ef11d409471",
"assets/assets/images/Butter%2520naan.jpg": "dc50cba36360d86bd8a1f45fd478fc90",
"assets/assets/images/Chocolate%2520Lava%2520Cake.jpg": "a985b986272d6d72097aa58ab9fc320f",
"assets/assets/images/chole%2520bature.jpg": "325de0317b0d5c85f2ee37f35babf657",
"assets/assets/images/Cold%2520Coffee.jpg": "22977e593aae87597d5da981e0c25a62",
"assets/assets/images/Crispy%2520Corn.jpg": "5edb91de1b326d3915408e2c89a3fb3a",
"assets/assets/images/Dal%2520Makhani.jpg": "55ce072b28848a706ba0cb5b3dbf856b",
"assets/assets/images/Dal%2520Tadka.jpg": "45d29b3d84e21c3ab1c512db10be946b",
"assets/assets/images/Dry%2520Manchgurian.jpg": "93f6981e25f8ad7b32f094d8b4197d66",
"assets/assets/images/French%2520Fries.jpg": "7df31f9f6ba6e7de4681323a606eba49",
"assets/assets/images/Garlic%2520Naan.jpg": "d361f7e58506beb3131e1836f07b6010",
"assets/assets/images/google.png": "ca2f7db280e9c773e341589a81c15082",
"assets/assets/images/Gulab%2520Jamun.jpg": "6593193262345fc2f9b090cab5533f8c",
"assets/assets/images/Jeera%2520Rice.jpg": "529603468c404ccc6d1c80a00dd5c762",
"assets/assets/images/Kadai%2520Paneer.jpg": "aa31b2fbece272af37f4cf34ba083068",
"assets/assets/images/Lime%2520Soda.jpg": "4efec3ca3d7cbcd9d37f0a978367309b",
"assets/assets/images/loginbg.jpg": "c42e29088364d08e4e33e37c4b4360d2",
"assets/assets/images/Mango%2520Lassi.jpg": "8e83ce074630d9d861c6838bc565b341",
"assets/assets/images/margherita%2520pizza.jpg": "2dfbf26cc08b32aed2b6e20a103130a8",
"assets/assets/images/Masala%2520Tea.jpg": "a9bbbea07c625c7192e2829393b47897",
"assets/assets/images/Mineral%2520Water.jpg": "83cae07f0246b61ff132fb0afb2188e8",
"assets/assets/images/Paneer%2520Butter%2520Masala.jpg": "01890272dcbb56c31877ad143070ac20",
"assets/assets/images/Paneer%2520Tikka.jpg": "d49e48d5e1ccea623778c28dd22fcd5c",
"assets/assets/images/panner%2520lababdar.jpg": "971e374d5e50dd570b8e419d2c429fab",
"assets/assets/images/Red%2520Sauce%2520Pasta.jpg": "5960a1d0d3f5901b91dda7bf474989bc",
"assets/assets/images/restaurant.jpg": "289f8fd20525f2e027018ee3e61ec3db",
"assets/assets/images/signupbg.jpg": "7b3dba0dee1e500e4390de5c09dae4f1",
"assets/assets/images/Soft%2520Drinks.jpg": "3ebbbbb150533aac0ca5547bc5561352",
"assets/assets/images/Spring%2520Rolls.jpg": "33191663d3fa833f5f99ecc82b69d3b7",
"assets/assets/images/Steam%2520Rice.jpg": "1b52da83e377385262767dd21d13b588",
"assets/assets/images/Strawberry%2520Mocktail.jpg": "d1d4150496bf046f38fcae4bc726b671",
"assets/assets/images/Tandoori%2520Roti.jpg": "dedc6fc938a787c3a93c34d38fa319ae",
"assets/assets/images/tiramisu.jpg": "2e7dc1f71240ad380f4d8a5814333729",
"assets/assets/images/Veg%2520Biryani.jpg": "a18031d4a28b3627a1b253b46679fe87",
"assets/assets/images/Veg%2520Burger.jpg": "252dcb0479690831f2a67dd6bdc4a06e",
"assets/assets/images/veggie%2520paradise.jpg": "fbc9e221f34b04836beb433367a43941",
"assets/assets/images/White%2520Sauce%2520Pasta.jpg": "fb8e5fe16880f34c263a5ce73fd29e23",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "432d5ac8a5e429faa0902a8b9bad1183",
"assets/NOTICES": "eaace2a4dd09418574077e64d09d7aa1",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"flutter_bootstrap.js": "074062bdc05ddf6d85a637900d99a7e9",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "a6b6a880caa0fef0e34f6dd39c86a77b",
"/": "a6b6a880caa0fef0e34f6dd39c86a77b",
"main.dart.js": "ce0c1f981d3c21d93b8e3942d1989ce8",
"manifest.json": "ae2474aba56e78c234e95c833c9988d8",
"version.json": "c6d1d3cf933fe2324749bacdacf47ae6"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
