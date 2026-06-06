import { ConnectButton } from "@rainbow-me/rainbowkit";

export default function Header() {
  return (
    <header className="w-full flex items-center justify-between px-6 py-4 border-b border-gray-800 bg-black">
      <div className="text-white font-bold text-xl tracking-widest">CIPHER</div>
      <ConnectButton />
    </header>
  );
}
