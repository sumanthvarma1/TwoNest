import type { Metadata } from 'next';
import './style.css';
export const metadata: Metadata = { title: 'TwoNest', description: 'Meet your person. Build your home.' };
export default function Layout({ children }: Readonly<{children: React.ReactNode}>) { return <html lang="en"><body>{children}</body></html>; }
