import assert from "node:assert/strict";
import test from "node:test";
import {
  extractPackSize,
  normalizePriceSearchInput,
  parseEmbeddedProductOffers,
  parseMoney,
  searchPrices,
} from "../lib/price-intelligence";

test("normalizes price search input safely", () => {
  assert.deepEqual(normalizePriceSearchInput({
    query: "  Tetley Tea  ",
    pincode: "500 037",
    providers: ["demo", "jiomart", "unknown"],
    limit: 100,
  }), {
    query: "Tetley Tea",
    pincode: "500037",
    providers: ["demo", "jiomart"],
    limit: 30,
  });
});

test("parses rupee values and pack sizes", () => {
  assert.equal(parseMoney("₹1,078.00"), 1078);
  assert.equal(parseMoney("MRP Rs. 29.50"), 29.5);
  assert.equal(extractPackSize("Gold Drop Sunflower Oil 1 Litre"), "1l");
  assert.equal(extractPackSize("Whisper Sanitary Pads 20 pieces"), "20pcs");
});

test("demo provider returns useful grocery matches", async () => {
  const response = await searchPrices({ query: "tea", providers: ["demo"], limit: 3 });
  assert.equal(response.cached, false);
  assert.ok(response.offers.length >= 1);
  assert.equal(response.offers[0].currency, "INR");
  assert.match(response.offers.map((offer) => offer.productName).join(" "), /Tea/i);

  const cached = await searchPrices({ query: "tea", providers: ["demo"], limit: 3 });
  assert.equal(cached.cached, true);
  assert.equal(cached.offers[0].source, "cache");
});

test("unknown live providers are reported without failing the full lookup", async () => {
  const response = await searchPrices({ query: "milk", providers: ["demo", "blinkit"] });
  assert.ok(response.offers.some((offer) => offer.productName.includes("Milk")));
  assert.ok(response.warnings.some((warning) => warning.includes("Blinkit")));
});

test("parses embedded product offers from provider HTML", () => {
  const html = `
    <html><body>
      <script type="application/json">
        {"items":[{"name":"Tetley Classic Tea 250g","brand":"Tetley","sellingPrice":"₹165","mrp":"₹180","availability":"in stock","url":"https://example.test/tea"}]}
      </script>
    </body></html>
  `;
  const offers = parseEmbeddedProductOffers(html, "bigbasket", "BigBasket");
  assert.equal(offers.length, 1);
  assert.equal(offers[0].provider, "bigbasket");
  assert.equal(offers[0].sellingPrice, 165);
  assert.equal(offers[0].mrp, 180);
  assert.equal(offers[0].packSize, "250g");
  assert.equal(offers[0].unit, "kg");
});

test("bigbasket adapter uses fetched HTML when available", async () => {
  const fakeFetch = async () => new Response(`
    <script type="application/json">
      {"products":[{"productName":"Tata Tea Gold 500g","sellingPrice":318,"mrp":340}]}
    </script>
  `) as Response;

  const response = await searchPrices({ query: "tata tea", providers: ["bigbasket"] }, fakeFetch as typeof fetch);
  assert.equal(response.offers.length, 1);
  assert.equal(response.offers[0].providerLabel, "BigBasket");
  assert.equal(response.offers[0].sellingPrice, 318);
});
