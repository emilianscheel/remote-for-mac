import Image from "next/image";

export default function Home() {
  return (
    <main className="flex min-h-svh items-center justify-center px-6 py-16">
      <section aria-labelledby="product-name" className="flex w-full max-w-xs flex-col items-center text-center">
        <Image
          aria-hidden="true"
          alt=""
          className="mb-7 size-28 rounded-[1.65rem]"
          height={112}
          priority
          src="/Icon.png"
          width={112}
        />
        <h1 id="product-name" className="text-2xl font-medium tracking-[-0.035em] text-zinc-950 dark:text-zinc-50">
          Remote for Mac
        </h1>
        <a
          href="/Remote.for.Mac.dmg"
          className="mt-7 inline-flex items-center justify-center rounded-full bg-zinc-200 px-4 py-1.5 text-sm font-medium text-zinc-900 transition-colors hover:bg-zinc-300 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-zinc-900 active:bg-zinc-400 dark:bg-zinc-800 dark:text-zinc-50 dark:hover:bg-zinc-700 dark:focus-visible:outline-zinc-50 dark:active:bg-zinc-600"
        >
          Download
        </a>
      </section>
    </main>
  );
}
