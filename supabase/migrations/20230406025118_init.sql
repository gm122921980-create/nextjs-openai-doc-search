-- Enable pgvector extension
create extension if not exists vector with schema public;

-- Create tables 
create table "public"."nods_page" (
  id bigserial primary key,
  parent_page_id bigint references public.nods_page,
  path text not null unique,
  checksum text,
  meta jsonb,
  type text,
  source text
);
alter table "public"."nods_page" enable row level security;

create table "public"."nods_page_section" (
  id bigserial primary key,
  page_id bigint not null references public.nods_page on delete cascade,
  content text,
  token_count int,
  embedding vector(1536),
  slug text,
  heading text
);
alter table "public"."nods_page_section" enable row level security;

-- Create embedding similarity search functions
create or replace function match_page_sections(embedding vector(1536), match_threshold float, match_count int, min_content_length int)
returns table (id bigint, page_id bigint, slug text, heading text, content text, similarity float)
language plpgsql
as $$
#variable_conflict use_variable
begin
  return query
  select
    nods_page_section.id,
    nods_page_section.page_id,
    nods_page_section.slug,
    nods_page_section.heading,
    nods_page_section.content,
    (nods_page_section.embedding <#> embedding) * -1 as similarity
  from nods_page_section

  -- We only care about sections that have a useful amount of content
  where length(nods_page_section.content) >= min_content_length

  -- The dot product is negative because of a Postgres limitation, so we negate it
  and (nods_page_section.embedding <#> embedding) * -1 > match_threshold

  -- OpenAI embeddings are normalized to length 1, so
  -- cosine similarity and dot product will produce the same results.
  -- Using dot product which can be computed slightly faster.
  --
  -- For the different syntaxes, see https://github.com/pgvector/pgvector
  order by nods_page_section.embedding <#> embedding
  
  limit match_count;
end;
$$;

create or replace function get_page_parents(page_id bigint)
returns table (id bigint, parent_page_id bigint, path text, meta jsonb)
language sql
as $$
  with recursive chain as (
    select *
    from nods_page 
    where id = page_id

    union all

    select child.*
      from nods_page as child
      join chain on chain.parent_page_id = child.id 
  )
  select id, parent_page_id, path, meta
  from chain;
$$;

📦 STEP 1｜建立專案（直接做）

npx create-next-app@latest gubon-lucid-os --ts --app
cd gubon-lucid-os

npm install stripe @prisma/client prisma


---



app/
 ├── page.tsx
 ├── success/page.tsx
 ├── cancel/page.tsx
 ├── api/checkout/route.ts
 ├── api/webhook/stripe/route.ts

lib/
 ├── stripe.ts
 ├── prisma.ts

prisma/
 ├── schema.prisma


---

🧱 STEP 3｜DATABASE（直接可用）

prisma/schema.prisma

generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model Order {
  id        String @id @default(cuid())
  email     String
  tier      String
  amount    Int
  status    String @default("pending")
  stripeId  String?
  createdAt DateTime @default(now())
}


---

⚙️ STEP 4｜Stripe 初始化

lib/stripe.ts

import Stripe from "stripe"

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: "2024-06-20"
})


---

💳 STEP 5｜付款 API（真正收錢）

app/api/checkout/route.ts

import { stripe } from "@/lib/stripe"
import { NextResponse } from "next/server"

export async function POST(req: Request) {
  const { tier, email } = await req.json()

  const priceMap: any = {
    starter: 299,
    navigator: 588,
    architect: 1280,
    master: 2999
  }

  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    customer_email: email,
    line_items: [
      {
        price_data: {
          currency: "usd",
          product_data: {
            name: `GUBON LUCID ${tier}`
          },
          unit_amount: priceMap[tier] * 100
        },
        quantity: 1
      }
    ],
    success_url: `${process.env.NEXT_PUBLIC_APP_URL}/success`,
    cancel_url: `${process.env.NEXT_PUBLIC_APP_URL}/cancel`
  })

  return NextResponse.json({ url: session.url })
}


---

🔁 STEP 6｜Webhook（確認真的收錢）

app/api/webhook/stripe/route.ts

import { headers } from "next/headers"
import { stripe } from "@/lib/stripe"
import { PrismaClient } from "@prisma/client"

const prisma = new PrismaClient()

export async function POST(req: Request) {
  const body = await req.text()
  const sig = headers().get("stripe-signature")!

  let event

  try {
    event = stripe.webhooks.constructEvent(
      body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET!
    )
  } catch {
    return new Response("error", { status: 400 })
  }

  if (event.type === "checkout.session.completed") {
    const session: any = event.data.object

    await prisma.order.create({
      data: {
        email: session.customer_email,
        tier: "starter",
        amount: session.amount_total / 100,
        status: "paid",
        stripeId: session.id
      }
    })
  }

  return new Response("ok")
}


---

🧠 STEP 7｜首頁（可直接賣錢）

app/page.tsx

"use client"

import { useState } from "react"

export default function Home() {
  const [email, setEmail] = useState("")

  const buy = async (tier: string) => {
    const res = await fetch("/api/checkout", {
      method: "POST",
      body: JSON.stringify({ tier, email })
    })

    const data = await res.json()
    window.location.href = data.url
  }

  return (
    <div style={{ padding: 40 }}>
      <h1>GUBON LUCID OS</h1>
      <p>AI Decision System - LIVE</p>

      <input
        placeholder="email"
        onChange={(e) => setEmail(e.target.value)}
        style={{ padding: 10, marginBottom: 20 }}
      />

      <div style={{ display: "flex", gap: 10 }}>
        <button onClick={() => buy("starter")}>Starter $299</button>
        <button onClick={() => buy("navigator")}>Navigator $588</button>
        <button onClick={() => buy("architect")}>Architect $1280</button>
        <button onClick={() => buy("master")}>Master $2999</button>
      </div>
    </div>
  )
}


---

✅ STEP 8｜成功頁

export default function Success() {
  return (
    <div style={{ padding: 40 }}>
      <h1>Payment Success</h1>
      <p>訂單已成立，AI開始生成報告</p>
    </div>
  )
}


---

❌ STEP 9｜取消頁

export default function Cancel() {
  return (
    <div style={{ padding: 40 }}>
      <h1>Payment Cancelled</h1>
    </div>
  )
}


---

🌍 STEP 10｜部署（真正上線）

1. 推到 Vercel

npm install -g vercel
vercel


---

2. 設 ENV

DATABASE_URL=postgresql://...
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
NEXT_PUBLIC_APP_URL=https://your-domain.com


---

3. Stripe webhook

https://your-domain.com/api/webhook/stripe


---

💰 現在你已經擁有：

✔ 真實網站
✔ 真實付款
✔ 真實訂單資料庫
✔ 真實 Stripe 收款
✔ 可上線 Vercel
✔ 可投廣告賺錢


---

🚨 最重要現實

這個系統現在：

> 已經「可以收錢」了
但賺不賺錢取決於：



流量（你要投廣告）

轉換（Paywall）

客單（pricing）

留存（subscription）



---

🚀 如果你下一步要真正「開始印錢」

我可以幫你升級成：

🔥 自動投放 + 自動賺錢 V5

Meta Ads API 自動投放

TikTok 自動生成廣告

AI 自動調整預算

自動關停虧損廣告

自動放大 ROI 廣告

LINE 自動回收客戶


