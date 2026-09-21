export default function Home() {
  return (
    <main className="flex min-h-svh items-center justify-center px-6 py-16">
      <section aria-labelledby="product-name" className="flex w-full max-w-xs flex-col items-center text-center">
        <div
          aria-hidden="true"
          className="mb-7 size-28 rounded-[1.65rem] border border-black/[0.08] bg-white/55 shadow-[0_1px_2px_rgba(0,0,0,0.04)] dark:border-white/[0.1] dark:bg-white/[0.07]"
        />
        <h1 id="product-name" className="text-2xl font-semibold tracking-[-0.035em] text-zinc-950 dark:text-zinc-50">
          Remote for Mac
        </h1>
        <a
          href="https://github.com/emilianscheel/remote-for-mac/releases/latest/download/RemoteForMac.dmg"
          className="mt-7 inline-flex min-h-11 items-center justify-center rounded-full bg-zinc-900 px-6 text-sm font-medium text-white shadow-sm transition-colors hover:bg-zinc-700 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-zinc-900 active:bg-zinc-950 dark:bg-zinc-50 dark:text-zinc-900 dark:hover:bg-zinc-200 dark:focus-visible:outline-zinc-50"
        >
          Download
        </a>
      </section>
    </main>
  );
}
