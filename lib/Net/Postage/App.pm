package Net::Postage::App;

use strict;
use warnings;
use JSON;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use MIME::Base64;
use File::Spec;

our $VERSION = '0.03';

sub new {
    my ($class,%args) = @_;
    my $args = \%args;
    my $self = {};
    $self->{data}->{api_key} = $args->{api_key};
    $self->{json} = JSON->new;
    $self->{url} = $args->{url} || "http://api.postageapp.com/v.1.0/send_message.json";
    die 'api_key argument is required' if !$self->{data}->{api_key};
    return bless($self, $class);
}

sub message {
    my ($self,%msg) = @_;
    my $message = \%msg;
    my $subject = $message->{subject} || die 'subject argument is required';
    my $from = $message->{from} || die 'from argument is required';
    my $reply_to = $message->{reply_to};
    my $text = $message->{textmessage};
    my $html = $message->{htmlmessage};
    my $template = $message->{template};
    my $variables = $message->{variables};
    my $extra_headers = $message->{headers};
    
    if (!$text && !$html && !$template){
        die 'You have to include (textmessage and/or htmlmessage) or a predefined template';
    }
    
    #do we have attachments
    if (my $attachments = $message->{attachments}) {
        use Data::Dumper;
        my @attachments;
        foreach my $file (@{$attachments}){
            my $hash = {};
            my ($vol,$dir,$filename) = File::Spec->splitpath( $file );
            ##get file content
            open(my $fh, '<', $file) or die "can't open file $file $!";
            my $content = do {local $/; <$fh>};
            close $fh;
            
            $self->{data}->{arguments}->{attachments}->{$filename} = {
                'content_type' => 'application/octet-stream',
                'content' => encode_base64($content)
            };
        }
    }
    
    ###combine arguments
    $self->{data}->{arguments}->{content}->{'text/plain'} = $text if $text;
    $self->{data}->{arguments}->{content}->{'text/html'} = $html if $html;
    $self->{data}->{arguments}->{'template'} = $template if $template;
    $self->{data}->{arguments}->{'variables'} = $variables if $variables;
    $self->{data}->{arguments}->{headers} = {
        "subject" => $subject,
        "from" => $from,
        "reply-to" => $reply_to
    };
    
    while( my ($key, $value) = each %$extra_headers ) {
        $self->{data}->{arguments}->{headers}->{$key} = $value;
    }
    
    return $self->{data};
}

sub to {
    my ($self,$rec) = @_;
    my %all_rec = ();
    my %hash = ();
    if (ref $rec ){    
        if (ref $rec eq 'HASH'){
            %hash = %{$rec};
        } elsif (ref $rec eq 'ARRAY'){
            %hash = map { $_ => 1 } @{$rec};
        }
        
        if ($self->{data}->{arguments}->{recipients}){
            %all_rec = (%hash, %{$self->{data}->{arguments}->{recipients}});
        } else {
            %all_rec = %hash;
        }
        
        $self->{data}->{arguments}->{recipients} = \%all_rec;
    } else{
        $self->{data}->{arguments}->{recipients}->{$rec} = 1;
    }
    
    return $self->{data};
}

sub send {  
    my $self = shift;
    my $json = $self->{json};
    my $data = $json->encode($self->{data});
    my $ua = LWP::UserAgent->new;
    my $url = $self->{url};
    my $req = $ua->post(
        $url,
        'Content-Type' => 'application/json',
        'Content'      => $data
    );
    
    my $response = $json->decode($req->{_content});
    $self->{data} = {};
    $self->{response} = $response;
}

sub is_success {
    my $self = shift;
    if ($self->{response}->{response}->{status} eq "ok"){
        return 1;
    } else {
        return 0;
    }
}

1;

__END__

=head1 NAME

Net::Postage::App - Perl extension for Postageapp.com API

=head1 SYNOPSIS

    use Net::Postage::App;  
    
    my $postage = Net::Postage::App->new(api_key => 'YOUR_PostageApp_API_KEY_HERE');
    
    ###next prepare your message
    $postage->message(
        from => 'your_name <your_email>', ##required
        subject => 'Hi This is a test message', ##subject line is required
        textmessage => 'Hi there this is a TEXT message test',
        htmlmessage => '<b>Hi there this is an HTML message test</b>',
        reply_to => 'no-reply@example.com',  ##optional
        headers => {
            'x-mailer' => 'Postage-App.pm'
            ##.. you can add custom headers here
        }
    );
    
    ###now add recipients
    ##You can add a single recipient
    $postage->to('test@example.com');
    
    ##You can add an array of recipients at once
    $postage->to(['test@example.com','test2@example2.com',...]);
    
    ##Or hash of recipients for variable replacement
    $postage->to({
        'test@example.com' => { first_name => 'Mahmoud', last_name => 'Mehyar', ... },
        'test2@example2.com' => { first_name => 'fName', last_name => 'lName', ... },
        #...
    });
    
    ##Last, do the send
    $postage->send();
    
    ###make sure the sending was suucessful, otherwise send again later
    if (!$postage->is_success){
        ###sending process wasn't successful, look up what was wrong
        ##you can access postageapp API response at $postage->{response}
        use Data::Dumper;
        print Dumper($postage->{response});
    }
    
    else {
        print "Your message sent successfully";
    }

=head1 DESCRIPTION

Perl interface to the Postageapp.com API

postageapp.com "From their website" Outsource the sending of your application generated email,
so your app can do what it does best... be awesome!

See http://postageapp.com

=head2 EXPORT

None by default.

=head1 SEE ALSO

For more information about postageapp API please visit their documentation page

http://postageapp.com/docs/api

=head1 AUTHOR

Mahmoud A Mehyar, E<lt>mamod.mehyar@gmail.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2013 by Mahmoud A. Mehyar

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
