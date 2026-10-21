import type {Metadata} from 'next';
import './globals.css';
export const metadata:Metadata={title:'THBS Field Assist · Operations',description:'THBS Field Assist — offline field reporting and connected operations, presented by the Torry Harris team.'};
export default function RootLayout({children}:{children:React.ReactNode}){
  // Browser extensions can add attributes to <html> before React hydrates.
  // Limit this escape hatch to the document root; page content still warns.
  return <html lang="en" suppressHydrationWarning><body>{children}</body></html>;
}
