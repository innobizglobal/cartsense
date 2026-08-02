export default function Home() {
  return (
    <main>
      <section className="service-card">
        <div className="brand-row">
          <span className="brand">CartSense</span>
          <span className="status"><span aria-hidden="true" />Online</span>
        </div>
        <p className="eyebrow">AI RECEIPT SERVICE</p>
        <h1>Better recognition for difficult grocery bills.</h1>
        <p className="lede">
          Receipt photos are processed securely for the CartSense Android app.
          Images are analyzed in memory and are not stored by this service.
        </p>
        <div className="details" aria-label="Service protections">
          <div><strong>Structured</strong><span>Items, taxes and totals</span></div>
          <div><strong>Validated</strong><span>Arithmetic and item counts</span></div>
          <div><strong>Protected</strong><span>Server-only AI credential</span></div>
        </div>
      </section>
    </main>
  );
}
